# frozen_string_literal: true

module Inventory
  class CheckLowStockJob < ApplicationJob
    queue_as :default

    def perform(ingredient_id)
      ingredient = Ingredient.find(ingredient_id)
      return unless ingredient.low_stock?

      Inventory::NotifyService.deliver_to_managers(
        ingredient: ingredient,
        message: "#{ingredient.name} is low: #{ingredient.quantity_on_hand} #{ingredient.unit} " \
                 "remaining (threshold: #{ingredient.reorder_threshold})"
      )
    end
  end
end
