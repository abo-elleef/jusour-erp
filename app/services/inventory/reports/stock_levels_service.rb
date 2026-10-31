# frozen_string_literal: true

module Inventory
  module Reports
    # Stock levels (مستويات المخزون) for building purchase orders: on hand against
    # each item's minimum and maximum, how fast it is being used, and what to order.
    #
    # An item at or below its minimum is ordered up to its maximum. Most items have
    # a minimum but no maximum (on SAQR: 313 minimums, 43 maximums), so without a
    # maximum the target is the minimum plus +cover_days+ of average usage — the
    # basis is shown per row so nobody mistakes an estimate for a configured level.
    class StockLevelsService
      USAGE_WINDOW_DAYS = 30
      DEFAULT_COVER_DAYS = 7
      STATUSES = %w[below_min ok over_max no_levels].freeze

      Row = Struct.new(:ingredient, :supplier, :on_hand, :min, :max, :avg_daily_usage,
                       :unit_cost_cents, :target, :target_basis, :suggested_base,
                       :order_unit, :order_quantity, :order_whole_units, keyword_init: true) do
        def status
          if min.zero? && max.zero? then "no_levels"
          elsif min.positive? && on_hand <= min then "below_min"
          elsif max.positive? && on_hand > max then "over_max"
          else "ok"
          end
        end

        def days_of_cover
          return nil unless avg_daily_usage.positive?

          on_hand.positive? ? (on_hand / avg_daily_usage).round(1) : 0
        end

        def order_cents
          (suggested_base * unit_cost_cents).round
        end
      end

      def initialize(location: nil, supplier: nil, category: nil, cover_days: DEFAULT_COVER_DAYS)
        @location = location
        @supplier = supplier
        @category = category
        @cover_days = cover_days
      end

      def call
        ingredients = scope.to_a
        return [] if ingredients.empty?

        ids = ingredients.map(&:id)
        levels = levels_for(ids)
        usage = usage_for(ids)
        costs = Inventory::LocationUnitCost.map_for(ingredients: ingredients, location: @location)

        ingredients.map do |ingredient|
          on_hand, min, max = levels.fetch(ingredient.id) do
            [ingredient.quantity_on_hand.to_d, ingredient.reorder_threshold.to_d, ingredient.max_quantity.to_d]
          end
          build_row(ingredient, on_hand, min, max, usage.fetch(ingredient.id, 0.to_d) / USAGE_WINDOW_DAYS,
                    costs.fetch(ingredient.id, 0))
        end
      end

      private

      def scope
        scope = Ingredient.active.includes(:ingredient_category, :unit_ref,
                                           { ingredient_units: :unit_ref }, { supplier_ingredients: :supplier })
        scope = scope.where(ingredient_category_id: @category.id) if @category
        scope = scope.where(id: SupplierIngredient.where(supplier_id: @supplier.id).select(:ingredient_id)) if @supplier
        if @location
          scope = scope.where(id: IngredientLocation.where(location_id: @location.id).select(:ingredient_id))
        end
        scope.order(:name)
      end

      # Location levels when looking at one location; otherwise the company-wide
      # figures on the ingredient itself (the fetch default above).
      def levels_for(ids)
        return {} unless @location

        IngredientLocation.where(location_id: @location.id, ingredient_id: ids)
          .pluck(:ingredient_id, :quantity_on_hand, :reorder_threshold, :max_quantity)
          .to_h { |id, on_hand, min, max| [id, [on_hand.to_d, min.to_d, max.to_d]] }
      end

      def usage_for(ids)
        since = (Date.current - USAGE_WINDOW_DAYS).beginning_of_day
        Ledger.scope(location: @location, ingredient_ids: ids)
          .where(stock_adjustments: { created_at: since.., adjustment_type: Ledger.usage_types(@location) })
          .group("stock_adjustments.ingredient_id")
          .sum(Arel.sql("-stock_adjustments.quantity_delta"))
          .transform_values(&:to_d)
      end

      def build_row(ingredient, on_hand, min, max, avg_daily, unit_cost)
        row = Row.new(ingredient: ingredient, supplier: supplier_for(ingredient), on_hand: on_hand,
                      min: min, max: max, avg_daily_usage: avg_daily, unit_cost_cents: unit_cost,
                      suggested_base: 0.to_d, order_quantity: 0.to_d, order_unit: ingredient.unit,
                      order_whole_units: false)
        return row unless row.status == "below_min"

        if max.positive?
          row.target = max
          row.target_basis = "max"
        else
          row.target = min + (avg_daily * @cover_days)
          row.target_basis = "usage"
        end
        # Negative on-hand is a recording gap (stock used before it was posted),
        # not stock owed to the shelf — ordering it back would buy thousands of
        # units of nothing. Order from zero; the negative stays visible on the row.
        apply_order_quantity(row, ingredient, [row.target - [on_hand, 0].max, 0].max)
      end

      # Orders go out in the purchase unit when one is configured, rounded up to
      # whole units — the same rule as the supplier purchase request.
      def apply_order_quantity(row, ingredient, needed_base)
        purchase = ingredient.purchase_unit_record
        if purchase && needed_base.positive?
          factor = purchase.base_units_per_unit.to_d
          row.order_quantity = (needed_base / factor).ceil
          row.order_unit = purchase.unit
          row.order_whole_units = true
          row.suggested_base = row.order_quantity * factor
        else
          row.order_quantity = needed_base.ceil(3)
          row.suggested_base = row.order_quantity
        end
        row
      end

      # The preferred link, else the only link; several unranked vendors give none
      # rather than a guess.
      def supplier_for(ingredient)
        links = ingredient.supplier_ingredients
        return links.first.supplier if links.size == 1

        preferred = links.select(&:preferred)
        preferred.size == 1 ? preferred.first.supplier : nil
      end
    end
  end
end
