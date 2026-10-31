# frozen_string_literal: true

module Inventory
  module Reports
    # Item movement card (كارت الصنف): every movement of one item over a period,
    # opening from everything before it, each row carrying its running balance in
    # quantity and value, and the period's in/out totals underneath.
    #
    # With no item chosen it is the same card folded to one line per item —
    # opening, in, out, closing — which is how an accountant scans for the item
    # worth opening.
    class ItemCardService
      # Closing quantity is opening + in - out by construction. Closing value is
      # valued afresh at the cost of the time (Ledger.balances_before), so it can
      # differ from opening value + in - out by the effect of cost changes.
      Totals = Struct.new(:ingredient, :opening_qty, :opening_value, :qty_in, :qty_out,
                          :value_in, :value_out, :closing_value, :count, :estimated, keyword_init: true) do
        def closing_qty = opening_qty + qty_in - qty_out
      end

      def initialize(start_date:, end_date:, ingredient: nil, location: nil, category: nil)
        @range = Ledger.period(start_date, end_date)
        @ingredient = ingredient
        @location = location
        @category = category
      end

      # The card's rows, oldest first, each with a running_qty that already
      # includes the opening balance. Window sums are evaluated before
      # LIMIT/OFFSET, so this relation can be paginated and every page still
      # carries the right running balance.
      def movements
        opening_qty, = opening
        Ledger.scope(location: @location, ingredient_ids: [@ingredient.id])
          .where(stock_adjustments: { created_at: @range })
          .select(
            "stock_adjustments.*",
            "#{opening_qty.to_d} + SUM(stock_adjustments.quantity_delta) " \
            "OVER (ORDER BY stock_adjustments.created_at, stock_adjustments.id) AS running_qty"
          )
          .includes(:user, :location)
          .order("stock_adjustments.created_at", "stock_adjustments.id")
      end

      def totals
        summaries_for([@ingredient.id]).first ||
          Totals.new(ingredient: @ingredient, opening_qty: 0.to_d, opening_value: 0, qty_in: 0.to_d,
                     qty_out: 0.to_d, value_in: 0, value_out: 0, closing_value: 0, count: 0, estimated: 0)
      end

      # One line per item that had stock before the period or moved during it.
      def summaries
        summaries_for(Ledger.ingredient_ids_for(@category))
      end

      private

      def opening
        @opening ||= Ledger.balances_before(@range.begin, location: @location, ingredient_ids: [@ingredient.id])
                           .fetch(@ingredient.id, [0.to_d, 0])
      end

      def summaries_for(ids)
        openings = Ledger.balances_before(@range.begin, location: @location, ingredient_ids: ids)
        closings = Ledger.balances_before(@range.end, location: @location, ingredient_ids: ids)
        periods = Ledger.period_totals(@range, location: @location, ingredient_ids: ids)
        active_ids = (openings.reject { |_, (qty, _)| qty.zero? }.keys + periods.keys).uniq
        ingredients = Ingredient.where(id: active_ids).includes(:ingredient_category).index_by(&:id)

        active_ids.filter_map do |id|
          ingredient = ingredients[id] or next
          qty, value = openings.fetch(id, [0.to_d, 0])
          period = periods.fetch(id, {})
          Totals.new(
            ingredient: ingredient, opening_qty: qty, opening_value: value,
            qty_in: period[:qty_in] || 0.to_d, qty_out: period[:qty_out] || 0.to_d,
            value_in: period[:value_in] || 0, value_out: period[:value_out] || 0,
            closing_value: closings.fetch(id, [0, 0])[1],
            count: period[:count] || 0, estimated: period[:estimated] || 0
          )
        end.sort_by { |row| row.ingredient.name.to_s.downcase }
      end
    end
  end
end
