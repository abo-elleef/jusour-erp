# frozen_string_literal: true

class StockAdjustment < ApplicationRecord
  include UnitReferenced

  belongs_to :ingredient
  belongs_to :user
  belongs_to :location, optional: true
  belongs_to :stock_batch, optional: true
  belongs_to :stock_transfer, optional: true
  references_unit :unit, column: :unit_id

  ADJUSTMENT_TYPES = %w[
    delivery vendor_invoice manual_add manual_remove
    waste_spoilage waste_prep waste_overproduction
    cycle_count_correction consumption
    production_consumption production_output
    transfer_out transfer_in
  ].freeze

  # Set by manual adjust flows so a location-scoped adjustment also maintains the
  # FIFO batch ledger (create a batch on a manual add, deduct FIFO on a removal).
  # Service flows (transfers, receiving, production, consumption) manage their own
  # batches and must leave this false to avoid double-counting.
  attr_accessor :maintain_batches
  # Optional override for the cost stamped on a newly created overage batch when
  # +maintain_batches+ is true. Defaults to the ingredient master cost.
  attr_accessor :batch_cost_per_unit_cents

  validates :quantity_delta, numericality: true
  validate :quantity_delta_not_zero
  validates :adjustment_type, inclusion: { in: ADJUSTMENT_TYPES }

  after_create :update_ingredient_stock
  after_create :sync_location_batches, if: :maintain_batches_for_location?

  private

  def quantity_delta_not_zero
    return unless quantity_delta.to_d.zero?

    errors.add(:quantity_delta, "must not be zero")
  end

  def update_ingredient_stock
    if location_id.present?
      # Adjust the location; its roll-up recomputes the ingredient's global
      # on-hand as the sum of all locations, so the two stay consistent.
      il = IngredientLocation.find_or_initialize_by(ingredient: ingredient, location: location)
      il.quantity_on_hand = il.quantity_on_hand.to_d + quantity_delta.to_d
      il.save!
    else
      ingredient.update_columns(quantity_on_hand: ingredient.quantity_on_hand.to_d + quantity_delta.to_d)
    end
  end

  def maintain_batches_for_location?
    maintain_batches && location_id.present?
  end

  # Keep the location's batch ledger in step with a manual adjustment so the
  # stock is FIFO-costed and transferable. Adds create a batch at the override
  # or ingredient master cost; removals draw down existing batches oldest-first.
  def sync_location_batches
    if quantity_delta.to_d.positive?
      cost = batch_cost_per_unit_cents.nil? ? ingredient.cost_per_unit_cents : batch_cost_per_unit_cents
      ingredient.stock_batches.create!(
        location: location,
        quantity_received: quantity_delta,
        quantity_remaining: quantity_delta,
        cost_per_unit_cents: cost,
        received_on: Date.current,
        batch_reference: "ADJ-#{id}"
      )
    else
      draw_down_batches(quantity_delta.to_d.abs)
    end
  end

  def draw_down_batches(amount)
    remaining = amount
    ingredient.stock_batches.where(location: location).fifo_order.with_stock.each do |batch|
      break if remaining <= 0

      take = [batch.quantity_remaining.to_d, remaining].min
      batch.update!(quantity_remaining: batch.quantity_remaining.to_d - take)
      remaining -= take
    end
  end
end
