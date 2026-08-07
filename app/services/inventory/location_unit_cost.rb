# frozen_string_literal: true

module Inventory
  # Unit cost for an ingredient at a location from remaining batch WAC,
  # falling back to latest supplier price then the ingredient master cost.
  class LocationUnitCost
    def self.call(ingredient:, location:)
      map_for(ingredients: [ingredient], location: location).fetch(ingredient.id)
    end

    # Returns { ingredient_id => cost_cents } for all given ingredients.
    def self.map_for(ingredients:, location:)
      ingredients = Array(ingredients).compact.uniq
      return {} if ingredients.empty?

      if location.blank?
        return ingredients.to_h { |ing| [ing.id, ing.cost_per_unit_cents.to_i] }
      end

      ids = ingredients.map(&:id)
      batches_by_ingredient = StockBatch
        .where(ingredient_id: ids, location_id: location.id)
        .with_stock
        .group_by(&:ingredient_id)

      history_by_ingredient = latest_supplier_prices(ids)

      ingredients.to_h do |ingredient|
        [
          ingredient.id,
          resolve(
            ingredient: ingredient,
            batches: batches_by_ingredient[ingredient.id] || [],
            history_price: history_by_ingredient[ingredient.id]
          )
        ]
      end
    end

    def self.resolve(ingredient:, batches:, history_price:)
      wac = weighted_average_cents(batches)
      return wac unless wac.nil?

      return history_price unless history_price.nil?

      ingredient.cost_per_unit_cents.to_i
    end
    private_class_method :resolve

    def self.weighted_average_cents(batches)
      total_qty = 0.to_d
      total_value = 0.to_d

      batches.each do |batch|
        qty = batch.quantity_remaining.to_d
        next if qty <= 0

        total_qty += qty
        total_value += qty * batch.cost_per_unit_cents.to_i
      end

      return nil if total_qty.zero?

      (total_value / total_qty).round
    end
    private_class_method :weighted_average_cents

    def self.latest_supplier_prices(ingredient_ids)
      rows = SupplierPriceHistory
        .where(ingredient_id: ingredient_ids)
        .order(effective_date: :desc, created_at: :desc)
        .select(:ingredient_id, :price_cents)

      rows.each_with_object({}) do |row, memo|
        memo[row.ingredient_id] ||= row.price_cents.to_i
      end
    end
    private_class_method :latest_supplier_prices
  end
end
