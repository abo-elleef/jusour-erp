# frozen_string_literal: true

module Inventory
  class CheckLowStockJob < ApplicationJob
    queue_as :default

    def perform(ingredient_id)
      ingredient = Ingredient.unscoped.find(ingredient_id)
      with_company(ingredient.company) do
        return unless ingredient.low_stock?
        return if ingredient.stock_alerts_suppressed?

        Inventory::NotifyService.deliver_to_managers(
          ingredient: ingredient,
          message_key: "low_stock",
          message_params: {
            ingredient_id: ingredient.id,
            name: ingredient.name,
            on_hand: ingredient.quantity_on_hand,
            unit: ingredient.unit,
            threshold: ingredient.reorder_threshold
          }
        )
      end
    end
  end
end
