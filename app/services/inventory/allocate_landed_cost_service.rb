# frozen_string_literal: true

module Inventory
  # Allocates a shipment's pooled landed costs across its stock batches and sets
  # each batch's true landed unit cost.
  #
  # Default split is by value (batch qty × provisional unit cost); a manual
  # override may fix a batch's allocation, with the remaining pool split by value
  # across the rest. Re-runnable: the provisional (supplier) cost is captured on
  # each batch so finalizing again after more costs arrive recomputes from the
  # baseline rather than compounding.
  class AllocateLandedCostService
    Row = Struct.new(:batch, :ingredient, :quantity, :provisional_cost_cents,
                     :allocated_cents, :landed_unit_cents, :final_unit_cents, keyword_init: true)

    def initialize(shipment, overrides: {})
      @shipment = shipment
      # { batch_id => allocated_cents }
      @overrides = (overrides || {}).transform_keys(&:to_s).transform_values(&:to_i)
    end

    # Compute the allocation without persisting (for the preview UI).
    def preview
      build_rows
    end

    # Persist the allocation onto the batches and mark the shipment finalized.
    def finalize!
      rows = build_rows
      ActiveRecord::Base.transaction do
        rows.each do |row|
          row.batch.update!(
            provisional_cost_per_unit_cents: row.provisional_cost_cents,
            cost_per_unit_cents: row.final_unit_cents
          )
        end
        @shipment.update!(status: "finalized", finalized_at: Time.current)
      end
      rows
    end

    private

    def build_rows
      batches = @shipment.stock_batches.includes(:ingredient).to_a
      pool = @shipment.total_costs_cents

      base_for = ->(b) { (b.provisional_cost_per_unit_cents || b.cost_per_unit_cents).to_i }
      value_for = ->(b) { b.quantity_received.to_d * base_for.call(b) }

      overridden = batches.select { |b| @overrides.key?(b.id) }
      fixed_total = overridden.sum { |b| @overrides[b.id] }
      auto_batches = batches - overridden
      auto_value_total = auto_batches.sum { |b| value_for.call(b) }
      remaining_pool = pool - fixed_total

      batches.map do |batch|
        provisional = base_for.call(batch)
        allocated =
          if @overrides.key?(batch.id)
            @overrides[batch.id]
          elsif auto_value_total.positive?
            (remaining_pool * (value_for.call(batch) / auto_value_total)).round
          else
            0
          end

        qty = batch.quantity_received.to_d
        landed_unit = qty.nonzero? ? (allocated.to_d / qty).round : 0

        Row.new(
          batch: batch, ingredient: batch.ingredient, quantity: qty,
          provisional_cost_cents: provisional, allocated_cents: allocated,
          landed_unit_cents: landed_unit, final_unit_cents: provisional + landed_unit
        )
      end
    end
  end
end
