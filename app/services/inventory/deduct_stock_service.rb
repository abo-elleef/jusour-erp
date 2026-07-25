# frozen_string_literal: true

module Inventory
  class DeductStockService
    def initialize(order)
      @order = order
    end

    def call
      @order.order_items
            .includes(
              menu_item: { recipes: :ingredient },
              order_item_modifiers: { modifier: { modifier_recipes: :ingredient } }
            )
            .each do |item|
        next unless item.menu_item_id

        # Accumulate all ingredient quantities in one pass to avoid double FIFO entries
        totals = Hash.new(0)

        item.menu_item.recipes.each do |recipe|
          totals[recipe.ingredient] += recipe.base_quantity_used * item.quantity
        end

        item.order_item_modifiers.each do |oim|
          oim.modifier.modifier_recipes.each do |mr|
            totals[mr.ingredient] += mr.quantity.to_d * item.quantity
          end
        end

        totals.each do |ingredient, quantity|
          next if quantity.zero?
          deduct_fifo(ingredient, quantity)
        end
      end
    end

    private

    def deduct_fifo(ingredient, quantity_needed)
      remaining = quantity_needed

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
        adjustment_type: "consumption",
        reason_notes: "Auto-deducted from Order #{@order.order_number}"
      )

      Inventory::CheckLowStockJob.perform_later(ingredient.id) if ingredient.reload.low_stock?
    end
  end
end
