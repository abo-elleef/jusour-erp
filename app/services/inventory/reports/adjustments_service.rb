# frozen_string_literal: true

module Inventory
  module Reports
    # Stock adjustments (التسويات المخزنية) valued at the cost each one recorded,
    # with surpluses and deficits kept apart. Netting them would hide the story: a
    # store that is 5,000 over on one item and 5,000 short on another nets to zero
    # and looks perfect.
    class AdjustmentsService
      # Corrections to the count. Waste and clearing a location are deliberate
      # write-offs rather than corrections, so they are offered but off by default.
      DEFAULT_TYPES = %w[cycle_count_correction manual_add manual_remove].freeze
      AVAILABLE_TYPES = (DEFAULT_TYPES + %w[waste_spoilage waste_prep waste_overproduction clear_all_stock]).freeze

      Row = Struct.new(:ingredient, :quantity, :value_cents, :count, :estimated, keyword_init: true)
      Result = Struct.new(:surplus, :deficit, keyword_init: true) do
        def surplus_cents = surplus.sum(&:value_cents)
        def deficit_cents = deficit.sum(&:value_cents)
        def net_cents = surplus_cents - deficit_cents
        def estimated_count = (surplus + deficit).sum(&:estimated)
        def empty? = surplus.empty? && deficit.empty?
      end

      def self.normalize_types(types)
        picked = Array(types).map(&:to_s) & AVAILABLE_TYPES
        picked.presence || DEFAULT_TYPES
      end

      def initialize(start_date:, end_date:, types:, location: nil, category: nil)
        @range = Ledger.period(start_date, end_date)
        @types = types
        @location = location
        @category = category
      end

      def call
        sums = Ledger.scope(location: @location, ingredient_ids: Ledger.ingredient_ids_for(@category))
          .where(stock_adjustments: { created_at: @range, adjustment_type: @types })
          .group("stock_adjustments.ingredient_id", Arel.sql("stock_adjustments.quantity_delta > 0"))
          .pluck(
            Arel.sql("stock_adjustments.ingredient_id"),
            Arel.sql("stock_adjustments.quantity_delta > 0"),
            Arel.sql("SUM(ABS(stock_adjustments.quantity_delta))"),
            Arel.sql("SUM(ABS(#{Ledger::VALUE_SQL}))"),
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE stock_adjustments.unit_cost_estimated)")
          )
        ingredients = Ingredient.where(id: sums.map(&:first).uniq).includes(:ingredient_category).index_by(&:id)

        rows = sums.filter_map do |id, surplus, qty, value, count, estimated|
          ingredient = ingredients[id] or next
          [surplus, Row.new(ingredient: ingredient, quantity: qty.to_d, value_cents: value.to_i,
                            count: count, estimated: estimated)]
        end
        by_value = ->(list) { list.map(&:last).sort_by { |row| [-row.value_cents, row.ingredient.name.to_s] } }

        Result.new(surplus: by_value.(rows.select(&:first)), deficit: by_value.(rows.reject(&:first)))
      end
    end
  end
end
