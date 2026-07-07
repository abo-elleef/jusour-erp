# frozen_string_literal: true

module Inventory
  class DeductStockService
    def initialize(order)
      @order = order
    end

    def call
      @order.order_items.each do |item|
        next unless item.menu_item_id

        item.menu_item.recipes.includes(:ingredient).each do |recipe|
          quantity_needed = recipe.base_quantity_used * item.quantity
          deduct_fifo(recipe.ingredient, quantity_needed)
        end
      end
    end

    private

    def deduct_fifo(ingredient, quantity_needed)
      remaining = quantity_needed

      ingredient.stock_batches.fifo_order.with_stock.each do |batch|
        break if remaining <= 0

        deductable = [batch.quantity_remaining.to_d, remaining].min
        batch.update!(quantity_remaining: batch.quantity_remaining.to_d - deductable)
        remaining -= deductable
      end

      StockAdjustment.create!(
        ingredient: ingredient,
        user: @order.user,
        quantity_delta: -quantity_needed,
        adjustment_type: "consumption",
        reason_notes: "Auto-deducted from Order #{@order.order_number}"
      )

      Inventory::CheckLowStockJob.perform_later(ingredient.id) if ingredient.reload.low_stock?
    end
  end
end
