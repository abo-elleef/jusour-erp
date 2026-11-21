# frozen_string_literal: true

module Inventory
  class DeductStockService
    def initialize(order)
      @order = order
    end

    def call
      @order.order_items
            .includes(
              menu_item: { recipes: [:unit_ref, { ingredient: :ingredient_units }] },
              order_item_modifiers: { modifier: { modifier_recipes: [:unit_ref, { ingredient: :ingredient_units }] } }
            )
            .each do |item|
        next unless item.menu_item_id

        # Netted per ingredient in one pass, so one FIFO draw per ingredient per line.
        totals = Inventory::LineConsumption.totals(
          menu_item: item.menu_item,
          modifiers: item.order_item_modifiers.map(&:modifier),
          units: item.quantity
        )

        totals.each do |ingredient, quantity|
          next if quantity.zero?
          deduct_fifo(ingredient, quantity)
        end
      end
    end

    private

    def deduct_fifo(ingredient, quantity_needed)
      remaining = quantity_needed
      # Read before the draw-down below moves the average it is taken from.
      unit_cost_cents = Inventory::LocationUnitCost.call(ingredient: ingredient, location: @order.location)

      # Consume from the selling location's own FIFO batches; the location-scoped
      # adjustment then rolls the location on-hand up into the global total.
      batches = ingredient.stock_batches.fifo_order.with_stock
      batches = batches.where(location: @order.location) if @order.location
      batches.each do |batch|
        break if remaining <= 0

        deductable = [batch.quantity_remaining.to_d, remaining].min
        batch.update!(quantity_remaining: batch.quantity_remaining.to_d - deductable)
        remaining -= deductable
      end

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @order.user,
        location: @order.location,
        quantity_delta: -quantity_needed,
        unit_cost_cents: unit_cost_cents,
        adjustment_type: "consumption",
        reason_notes: "Auto-deducted from Order #{@order.order_number}"
      )

      Inventory::CheckLowStockJob.perform_later(ingredient.id) if ingredient.reload.low_stock?
    end
  end
end
