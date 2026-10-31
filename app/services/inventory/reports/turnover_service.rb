# frozen_string_literal: true

module Inventory
  module Reports
    # Inventory turnover (معدل دوران المخزون): how many times the average stock
    # was used up over the period, and the same figure as days of stock held.
    #
    #   turnover = value used ÷ average stock value
    #   average  = (opening value + closing value) ÷ 2
    #   days     = days in period ÷ turnover
    #
    # Usage is valued at the cost each movement recorded and stock balances at
    # the cost of the time (Ledger.balances_before), so a past period always
    # reports the same turnover. Per item the quantity-based
    # turnover is shown too; it ignores price changes and is the cleaner read for
    # a single item. An item whose average stock is zero or negative (negative
    # on-hand is allowed) has no meaningful turnover and is flagged instead.
    class TurnoverService
      Row = Struct.new(:ingredient, :opening_qty, :closing_qty, :opening_value, :closing_value,
                       :used_qty, :used_value, keyword_init: true) do
        def average_qty = (opening_qty + closing_qty) / 2
        def average_value = (opening_value + closing_value) / 2.0

        def turnover
          return nil unless average_value.positive?

          (used_value / average_value).round(2)
        end

        def quantity_turnover
          return nil unless average_qty.positive?

          (used_qty / average_qty).round(2)
        end
      end

      Result = Struct.new(:rows, :days, keyword_init: true) do
        def used_value = rows.sum(&:used_value)
        def average_value = rows.sum(&:average_value)

        def turnover
          return nil unless average_value.positive?

          (used_value / average_value).round(2)
        end

        def days_of_stock(row_or_total = self)
          rate = row_or_total.turnover
          rate&.positive? ? (days / rate).round(1) : nil
        end
      end

      def initialize(start_date:, end_date:, location: nil, category: nil)
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @range = Ledger.period(@start_date, @end_date)
        @location = location
        @category = category
      end

      def call
        ids = Ledger.ingredient_ids_for(@category)
        openings = Ledger.balances_before(@range.begin, location: @location, ingredient_ids: ids)
        closings = Ledger.balances_before(@range.end, location: @location, ingredient_ids: ids)
        used = usage(ids)

        active_ids = (closings.reject { |_, (qty, _)| qty.zero? }.keys + used.keys).uniq
        ingredients = Ingredient.where(id: active_ids).includes(:ingredient_category).index_by(&:id)

        rows = active_ids.filter_map do |id|
          ingredient = ingredients[id] or next
          open_qty, open_value = openings.fetch(id, [0.to_d, 0])
          close_qty, close_value = closings.fetch(id, [0.to_d, 0])
          used_qty, used_value = used.fetch(id, [0.to_d, 0])
          Row.new(ingredient: ingredient, opening_qty: open_qty, closing_qty: close_qty,
                  opening_value: open_value, closing_value: close_value,
                  used_qty: used_qty, used_value: used_value)
        end

        Result.new(rows: rows.sort_by { |row| [-(row.turnover || -1), row.ingredient.name.to_s] },
                   days: (@end_date - @start_date).to_i + 1)
      end

      private

      def usage(ids)
        Ledger.scope(location: @location, ingredient_ids: ids)
          .where(stock_adjustments: { created_at: @range, adjustment_type: Ledger.usage_types(@location) })
          .group("stock_adjustments.ingredient_id")
          .pluck(Arel.sql("stock_adjustments.ingredient_id"),
                 Arel.sql("SUM(-stock_adjustments.quantity_delta)"),
                 Arel.sql("SUM(-#{Ledger::VALUE_SQL})"))
          .to_h { |id, qty, value| [id, [qty.to_d, value.to_i]] }
      end
    end
  end
end
