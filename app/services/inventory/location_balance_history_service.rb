# frozen_string_literal: true

module Inventory
  # Rebuilds daily closing on-hand for a few ingredients at one location by
  # walking stock_adjustments forward from the balance at the start of the range.
  class LocationBalanceHistoryService
    MAX_INGREDIENTS = 6
    DEFAULT_DAYS = 30
    ALLOWED_DAYS = [30, 90].freeze

    def initialize(location:, ingredient_ids:, days: DEFAULT_DAYS, as_of: Date.current)
      @location = location
      @ingredient_ids = Array(ingredient_ids).map(&:presence).compact.uniq.first(MAX_INGREDIENTS)
      @days = ALLOWED_DAYS.include?(days.to_i) ? days.to_i : DEFAULT_DAYS
      @as_of = as_of.to_date
    end

    def call
      return [] if @ingredient_ids.empty?

      ingredients = Ingredient.active
        .joins(:ingredient_locations)
        .where(ingredient_locations: { location_id: @location.id })
        .where(id: @ingredient_ids)
        .order(:name)
        .to_a

      start_date = @as_of - (@days - 1)
      end_date = @as_of

      ingredients.map do |ingredient|
        {
          name: ingredient.name,
          data: daily_balances(ingredient, start_date, end_date)
        }
      end
    end

    private

    def daily_balances(ingredient, start_date, end_date)
      current = IngredientLocation
        .find_by(ingredient_id: ingredient.id, location_id: @location.id)
        &.quantity_on_hand.to_d

      start_time = start_date.beginning_of_day
      deltas_from_start = StockAdjustment
        .where(ingredient_id: ingredient.id, location_id: @location.id)
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
  end
end
