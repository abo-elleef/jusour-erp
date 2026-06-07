# frozen_string_literal: true

module Inventory
  class CheckLowStockJob < ApplicationJob
    queue_as :default

    def perform(ingredient_id)
      ingredient = Ingredient.unscoped.find(ingredient_id)
      with_company(ingredient.company) do
        return unless ingredient.low_stock?

        Inventory::NotifyService.deliver_to_managers(
          ingredient: ingredient,
          message_key: "low_stock",
          message_params: {
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
