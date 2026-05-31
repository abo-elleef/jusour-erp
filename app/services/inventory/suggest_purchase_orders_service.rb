# frozen_string_literal: true

module Inventory
  class SuggestPurchaseOrdersService
    def call
      suggestions = Ingredient.active.low_stock.filter_map do |ingredient|
        link = ingredient.supplier_ingredients.find_by(preferred: true) ||
               ingredient.supplier_ingredients.first
        next unless link

        {
          ingredient: ingredient,
          supplier: link.supplier,
          suggested_quantity: ingredient.reorder_threshold.to_d * 2,
          unit_price_cents: link.price_cents
        }
      end

      suggestions.group_by { |s| s[:supplier] }
    end
  end
end
