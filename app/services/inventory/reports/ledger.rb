# frozen_string_literal: true

module Inventory
  module Reports
    # Shared reading of the stock movement ledger for the valued inventory
    # reports. Quantities are always in each ingredient's base unit, and values
    # come from the unit cost each movement recorded when it happened
    # (stock_adjustments.unit_cost_cents), so a report reads the same next month
    # as it does today.
    #
    # Balance quantities are derived from the movements themselves — opening =
    # everything before the period, closing = opening + the period — so a report
    # always adds up row by row, even where a stored on-hand figure has drifted
    # from its ledger. Balance values are quantity x the cost of the time (see
    # balances_before), so they need not equal opening value + in - out: the gap
    # is the effect of cost changing while the stock sat there.
    module Ledger
      # Movements that take stock out of the business, as opposed to moving it
      # around or undoing a purchase. Day-close clears and count corrections are
      # in on purpose: a restaurant branch that doesn't post recipe consumption
      # records what it used exactly that way (SAQR's branches do). Summed with
      # their sign, so a count surplus offsets usage rather than being ignored.
      # Not usage: returns to a vendor, invoice reversals, merges, receipts.
      USAGE_TYPES = %w[
        consumption customer_sale production_consumption
        waste_spoilage waste_prep waste_overproduction
        clear_all_stock cycle_count_correction manual_remove
      ].freeze

      # Viewed from one location, sending stock to another location is how that
      # location's stock gets used — a warehouse's only "sale" is a transfer.
      # Company-wide it is just stock moving between shelves.
      LOCATION_USAGE_TYPES = (USAGE_TYPES + %w[transfer_out]).freeze

      VALUE_SQL = "ROUND(stock_adjustments.quantity_delta * COALESCE(stock_adjustments.unit_cost_cents, 0))"

      module_function

      def scope(location: nil, ingredient_ids: nil)
        scope = StockAdjustment.for_current_company
        scope = scope.where(location_id: location.id) if location
        scope = scope.where(ingredient_id: ingredient_ids) unless ingredient_ids.nil?
        scope
      end

      def usage_types(location)
        location ? LOCATION_USAGE_TYPES : USAGE_TYPES
      end

      def period(start_date, end_date)
        start_date.to_date.beginning_of_day..end_date.to_date.end_of_day
      end

      # { ingredient_id => [quantity, value_cents] } as it stood just before +at+.
      #
      # Quantity is the sum of movements. Value is NOT the sum of movement values:
      # receipts, transfers and write-offs were costed on different bases over
      # time (FIFO batches, averages, zero-cost seed stock), so that sum keeps
      # value on an item long after its quantity is gone. Instead each location's
      # quantity is valued at the unit cost of its latest movement — the location
      # average as it stood then. Negative stock is valued at zero, as in the
      # valuation report.
      def balances_before(at, location: nil, ingredient_ids: nil)
        rows = scope(location: location, ingredient_ids: ingredient_ids)
          .where(stock_adjustments: { created_at: ...at })
          .group("stock_adjustments.ingredient_id", "stock_adjustments.location_id")
          .pluck(Arel.sql("stock_adjustments.ingredient_id"),
                 Arel.sql("SUM(stock_adjustments.quantity_delta)"),
                 Arel.sql("(ARRAY_AGG(COALESCE(stock_adjustments.unit_cost_cents, 0) " \
                          "ORDER BY stock_adjustments.created_at DESC, stock_adjustments.id DESC))[1]"))

        rows.each_with_object(Hash.new { |h, k| h[k] = [0.to_d, 0] }) do |(id, qty, cost), memo|
          qty = qty.to_d
          memo[id][0] += qty
          memo[id][1] += (qty * cost.to_i).round if qty.positive?
        end.to_h
      end

      # Per-ingredient in/out quantities and values over a period.
      def period_totals(range, location: nil, ingredient_ids: nil)
        scope(location: location, ingredient_ids: ingredient_ids)
          .where(stock_adjustments: { created_at: range })
          .group("stock_adjustments.ingredient_id")
          .pluck(
            Arel.sql("stock_adjustments.ingredient_id"),
            Arel.sql("SUM(CASE WHEN quantity_delta > 0 THEN quantity_delta ELSE 0 END)"),
            Arel.sql("SUM(CASE WHEN quantity_delta < 0 THEN -quantity_delta ELSE 0 END)"),
            Arel.sql("SUM(CASE WHEN quantity_delta > 0 THEN #{VALUE_SQL} ELSE 0 END)"),
            Arel.sql("SUM(CASE WHEN quantity_delta < 0 THEN -#{VALUE_SQL} ELSE 0 END)"),
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE stock_adjustments.unit_cost_estimated)")
          )
          .to_h do |id, qty_in, qty_out, value_in, value_out, count, estimated|
            [id, { qty_in: qty_in.to_d, qty_out: qty_out.to_d, value_in: value_in.to_i,
                   value_out: value_out.to_i, count: count, estimated: estimated }]
          end
      end

      # Ingredient ids in a category (or every ingredient when none given), for
      # narrowing ledger queries.
      def ingredient_ids_for(category)
        category ? Ingredient.where(ingredient_category_id: category.id).pluck(:id) : nil
      end
    end
  end
end
