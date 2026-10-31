# frozen_string_literal: true

module Inventory
  module Reports
    # Stagnant items (الأصناف الراكدة): stock on hand that nothing has used for
    # +days+ days, valued at today's location average so the owner sees how much
    # money is sitting still.
    #
    # "Used" means a usage movement (see Ledger::USAGE_TYPES). Receiving more of
    # an item, or counting it, does not make it move — those are shown alongside
    # as the last movement of any kind, since "bought last week, never used" is
    # its own warning.
    class StagnantItemsService
      DEFAULT_DAYS = 30

      Row = Struct.new(:ingredient, :on_hand, :value_cents, :last_used_at, :last_moved_at,
                       keyword_init: true) do
        def days_since_used
          last_used_at && (Date.current - last_used_at.to_date).to_i
        end
      end

      def initialize(days: DEFAULT_DAYS, location: nil, category: nil)
        @days = days
        @location = location
        @category = category
      end

      def call
        holdings = on_hand_by_location
        return [] if holdings.empty?

        ids = holdings.keys
        last_used = last_movement(ids, types: Ledger.usage_types(@location))
        cutoff = (Date.current - @days).beginning_of_day
        stagnant_ids = ids.reject { |id| last_used[id] && last_used[id] >= cutoff }
        return [] if stagnant_ids.empty?

        last_moved = last_movement(stagnant_ids)
        ingredients = Ingredient.where(id: stagnant_ids).includes(:ingredient_category).index_by(&:id)
        values = values_for(ingredients.values, holdings)

        stagnant_ids.filter_map do |id|
          ingredient = ingredients[id] or next
          Row.new(ingredient: ingredient, on_hand: holdings[id].values.sum, value_cents: values[id],
                  last_used_at: last_used[id], last_moved_at: last_moved[id])
        end.sort_by { |row| [-row.value_cents, row.ingredient.name.to_s] }
      end

      private

      # { ingredient_id => { location_id => quantity } } for positive holdings of
      # active items. Negative on-hand is expected (end-of-day manufacturing) and
      # is not stock sitting on a shelf.
      def on_hand_by_location
        scope = IngredientLocation.joins(:ingredient).merge(Ingredient.active)
          .where("ingredient_locations.quantity_on_hand > 0")
        scope = scope.where(location_id: @location.id) if @location
        scope = scope.where(ingredients: { ingredient_category_id: @category.id }) if @category

        scope.pluck(:ingredient_id, :location_id, :quantity_on_hand)
          .each_with_object(Hash.new { |h, k| h[k] = {} }) do |(ingredient_id, location_id, qty), memo|
            memo[ingredient_id][location_id] = qty.to_d
          end
      end

      def last_movement(ids, types: nil)
        scope = Ledger.scope(location: @location, ingredient_ids: ids)
        # A count surplus is a usage-type row too, but finding more stock is not
        # using it — only stock going out counts as the item moving.
        scope = scope.where(stock_adjustments: { adjustment_type: types }).merge(StockAdjustment.removals) if types
        scope.group("stock_adjustments.ingredient_id").maximum("stock_adjustments.created_at")
      end

      # Each location's holding at that location's own average cost.
      def values_for(ingredients, holdings)
        location_ids = holdings.values.flat_map(&:keys).uniq
        Location.where(id: location_ids).each_with_object(Hash.new(0)) do |location, memo|
          costs = Inventory::LocationUnitCost.map_for(ingredients: ingredients, location: location)
          costs.each do |ingredient_id, cost|
            qty = holdings.dig(ingredient_id, location.id)
            memo[ingredient_id] += (qty * cost).round if qty
          end
        end
      end
    end
  end
end
