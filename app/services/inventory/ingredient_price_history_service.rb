# frozen_string_literal: true

module Inventory
  # Daily purchase price (per base stock unit) for one ingredient, across every
  # vendor — the companion series to IngredientBalanceHistoryService so the
  # balance chart can show what that stock cost over the same window.
  #
  # A price holds until a receipt changes it, so days without a receipt carry the
  # previous price forward. The carry-forward is seeded from the last price
  # recorded *before* the range, otherwise the line would start late and imply
  # the ingredient had no price until its first receipt inside the window.
  class IngredientPriceHistoryService
    def initialize(ingredient:, days: IngredientBalanceHistoryService::DEFAULT_DAYS, as_of: Date.current)
      @ingredient = ingredient
      @days = IngredientBalanceHistoryService::ALLOWED_DAYS.include?(days.to_i) ?
        days.to_i :
        IngredientBalanceHistoryService::DEFAULT_DAYS
      @as_of = as_of.to_date
    end

    # => { "2026-08-01" => 12.5, ... } in currency units, matching the other
    # money charts. Empty when no price was ever recorded up to the range end.
    def call
      start_date = @as_of - (@days - 1)
      end_date = @as_of

      running = price_before(start_date)
      changes = prices_by_day(start_date, end_date)

      (start_date..end_date).each_with_object({}) do |day, series|
        running = changes[day] if changes.key?(day)
        # No price known yet at this point in the window — leave the day out
        # rather than plotting a zero we'd be inventing.
        next if running.nil?

        series[day.to_s] = (running / 100.0).round(2)
      end
    end

    private

    def price_before(start_date)
      base_scope
        .where(effective_date: ...start_date)
        .most_recent_first
        .first&.price_cents
    end

    # One price per day. When a day carries several receipts, the one recorded
    # last is the price that stands — the same rule the invoice handler uses to
    # decide whether a price actually changed.
    def prices_by_day(start_date, end_date)
      base_scope
        .where(effective_date: start_date..end_date)
        .most_recent_first
        .each_with_object({}) { |row, memo| memo[row.effective_date] ||= row.price_cents }
    end

    def base_scope
      SupplierPriceHistory.where(ingredient_id: @ingredient.id)
    end
  end
end
