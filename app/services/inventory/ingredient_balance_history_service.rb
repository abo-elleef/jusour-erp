# frozen_string_literal: true

module Inventory
  # Rebuilds a single ingredient's daily closing on-hand by walking
  # stock-adjustment deltas forward from the balance at the start of the range.
  class IngredientBalanceHistoryService
    DEFAULT_DAYS = 7
    ALLOWED_DAYS = [1, 3, 7, 14, 30, 90].freeze

    # location: nil walks the company-wide balance; a location walks that
    # location's own, seeded from its IngredientLocation rather than the
    # ingredient's total. Same reconstruction either way.
    def initialize(ingredient:, days: DEFAULT_DAYS, as_of: Date.current, location: nil)
      @ingredient = ingredient
      @days = ALLOWED_DAYS.include?(days.to_i) ? days.to_i : DEFAULT_DAYS
      @as_of = as_of.to_date
      @location = location
    end

    def call
      start_date = @as_of - (@days - 1)
      end_date = @as_of
      current = opening_on_hand
      start_time = start_date.beginning_of_day

      deltas_from_start = scoped_adjustments
        .where("created_at >= ?", start_time)
        .order(:created_at)

      # Balance at the beginning of start_date, before that day's movements.
      running = current - deltas_from_start.sum(:quantity_delta)

      by_day = deltas_from_start
        .select { |adj| adj.created_at.to_date <= end_date }
        .group_by { |adj| adj.created_at.to_date }

      (start_date..end_date).each_with_object({}) do |day, series|
        (by_day[day] || []).each { |adj| running += adj.quantity_delta.to_d }
        series[day.to_s] = running.to_f.round(3)
      end
    end

    private

    def opening_on_hand
      return @ingredient.quantity_on_hand.to_d if @location.nil?

      IngredientLocation
        .find_by(ingredient_id: @ingredient.id, location_id: @location.id)
        &.quantity_on_hand.to_d
    end

    # A handful of movements carry no location (production runs, historically),
    # so a per-location walk cannot see them. That is why the location series is
    # only ever shown on its own, never summed against the company-wide line.
    def scoped_adjustments
      scope = StockAdjustment.where(ingredient_id: @ingredient.id)
      @location ? scope.where(location_id: @location.id) : scope
    end
  end
end
