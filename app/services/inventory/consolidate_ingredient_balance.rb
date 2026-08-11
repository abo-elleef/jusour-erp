# frozen_string_literal: true

module Inventory
  # Moves a source ingredient's on-hand balance into a target ingredient, per
  # location, then zeroes the source. Both records stay active — the source is a
  # vendor-named duplicate that maps to the same physical item as the target.
  #
  # Balance movement rides the existing StockAdjustment engine (maintain_batches),
  # so location balances, the global roll-up, and the FIFO/cost ledger all stay
  # consistent. The source's vendor names are captured as aliases on the target so
  # future invoices for that vendor item can be received straight onto the target.
  #
  # Preconditions (all validated): distinct records, same company, target active,
  # and identical base unit (a unit mismatch blocks rather than guessing).
  class ConsolidateIngredientBalance
    class Error < StandardError; end

    Result = Struct.new(:locations_moved, :quantity_moved, :aliases_captured, keyword_init: true)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(source:, target:, user:, capture_aliases: true)
      @source = source
      @target = target
      @user = user
      @capture_aliases = capture_aliases
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        moved = move_balances!
        captured = @capture_aliases ? capture_aliases! : 0
        Result.new(
          locations_moved: moved[:count],
          quantity_moved: moved[:total],
          aliases_captured: captured
        )
      end
    end

    private

    def validate!
      raise Error, "same_ingredient" if @source.id == @target.id
      raise Error, "different_company" if @source.company_id != @target.company_id
      raise Error, "target_inactive" unless @target.active?
      raise Error, "unit_mismatch" unless @source.unit_id == @target.unit_id
    end

    # One out/in adjustment pair per location that holds stock. The "out" zeroes
    # the source location (and draws down its batches); the "in" adds the same
    # quantity to the target at the source's weighted-average cost.
    def move_balances!
      count = 0
      total = 0.to_d

      @source.ingredient_locations.where.not(quantity_on_hand: 0).includes(:location).each do |il|
        qty = il.quantity_on_hand.to_d
        next if qty.zero?

        location = il.location
        cost = LocationUnitCost.call(ingredient: @source, location: location)

        StockAdjustment.create!(
          ingredient: @source, user: @user, location: location,
          quantity_delta: -qty, adjustment_type: "consolidation_out",
          reason_notes: "Consolidated into #{@target.name} (#{@target.code})",
          maintain_batches: true
        )
        StockAdjustment.create!(
          ingredient: @target, user: @user, location: location,
          quantity_delta: qty, adjustment_type: "consolidation_in",
          reason_notes: "Consolidated from #{@source.name} (#{@source.code})",
          maintain_batches: true, batch_cost_per_unit_cents: cost
        )

        count += 1
        total += qty
      end

      { count: count, total: total }
    end

    # Preserve the source's vendor identity on the target so its name stays
    # searchable when receiving future invoices. Never clobbers an existing alias.
    def capture_aliases!
      captured = 0

      @source.supplier_ingredients.includes(:supplier).each do |si|
        alias_name = si.vendor_product_name.presence || @source.name
        target_si = @target.supplier_ingredients.find_or_initialize_by(supplier_id: si.supplier_id)

        if target_si.new_record?
          target_si.price_cents = si.price_cents
          target_si.vendor_product_name = alias_name
          target_si.vendor_sku = si.vendor_sku
          target_si.save!
          captured += 1
        elsif target_si.vendor_product_name.blank?
          target_si.update!(
            vendor_product_name: alias_name,
            vendor_sku: target_si.vendor_sku.presence || si.vendor_sku
          )
          captured += 1
        end
      end

      captured
    end
  end
end
