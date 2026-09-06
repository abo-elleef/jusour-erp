# frozen_string_literal: true

module Inventory
  # Movement between locations over time, built from completed stock transfers.
  #
  # Units: quantities are summed per ingredient only, never across them — a kg and
  # a piece do not add up. quantity_received is stored in the ingredient's base
  # unit (base_units_per returns 1 for it), so a straight sum is already in that
  # ingredient's own unit and every row carries the unit it is expressed in.
  #
  # The measure is quantity_received, not requested or sent: this report answers
  # what actually arrived at the destination.
  class TransferTrendsService
    GRANULARITIES = %w[day week month].freeze

    Row = Struct.new(:ingredient, :from_location, :to_location, :quantities,
                     :total, :transfer_ids, keyword_init: true) do
      # Always the ingredient's base unit — see the note on summing above.
      def unit
        ingredient.unit
      end

      # Ids, not a running count: one transfer carrying six ingredients is one
      # transfer, and a route rolls these up by union rather than by adding.
      def transfer_count
        transfer_ids.size
      end
    end

    Result = Struct.new(:rows, :periods, :period_labels, :granularity, :series,
                        :routes, :transfer_count, :ingredient_count, keyword_init: true)

    def initialize(start_date:, end_date:, from_location: nil, to_location: nil, granularity: nil)
      @start_date = start_date
      @end_date = end_date
      @from_location = from_location
      @to_location = to_location
      @granularity = GRANULARITIES.include?(granularity.to_s) ? granularity.to_s : default_granularity
    end

    def call
      transfers = load_transfers
      buckets = build_buckets(transfers)
      rows = build_rows(buckets)

      Result.new(
        rows: rows,
        periods: periods,
        period_labels: periods.map { |period| period_label(period) },
        granularity: @granularity,
        series: build_series(rows),
        routes: build_routes(rows),
        transfer_count: transfers.size,
        ingredient_count: rows.map { |row| row.ingredient.id }.uniq.size
      )
    end

    private

    # Starts from StockTransfer, which is Tenantable — querying lines directly
    # would sidestep the company default scope.
    def load_transfers
      scope = StockTransfer
        .where(status: "completed", transferred_on: @start_date..@end_date)
        .includes(:from_location, :to_location, stock_transfer_lines: :ingredient)
      scope = scope.where(from_location_id: @from_location.id) if @from_location
      scope = scope.where(to_location_id: @to_location.id) if @to_location
      scope.to_a
    end

    def build_buckets(transfers)
      buckets = Hash.new { |hash, key| hash[key] = { quantities: Hash.new(0.to_d), transfers: Set.new } }

      transfers.each do |transfer|
        period = period_for(transfer.transferred_on)
        transfer.stock_transfer_lines.each do |line|
          quantity = line.quantity_received.to_d
          # Lines that never arrived carry no movement; a completed transfer can
          # still hold them when it was closed short.
          next unless quantity.positive?

          key = [line.ingredient_id, transfer.from_location_id, transfer.to_location_id]
          bucket = buckets[key]
          bucket[:quantities][period] += quantity
          bucket[:transfers] << transfer.id
          bucket[:ingredient] ||= line.ingredient
          bucket[:from_location] ||= transfer.from_location
          bucket[:to_location] ||= transfer.to_location
        end
      end

      buckets
    end

    def build_rows(buckets)
      buckets.values.map { |bucket|
        Row.new(
          ingredient: bucket[:ingredient],
          from_location: bucket[:from_location],
          to_location: bucket[:to_location],
          quantities: bucket[:quantities],
          total: bucket[:quantities].values.sum,
          transfer_ids: bucket[:transfers]
        )
      }.sort_by { |row| [-row.total, row.ingredient.name.to_s.downcase] }
    end

    # One series per ingredient, summed over whatever routes are in scope. Every
    # period appears even when nothing moved, so the line reads as a trend rather
    # than joining across gaps.
    def build_series(rows)
      rows
        .group_by(&:ingredient)
        .map { |ingredient, ingredient_rows|
          totals = Hash.new(0.to_d)
          ingredient_rows.each { |row| row.quantities.each { |period, qty| totals[period] += qty } }
          {
            ingredient: ingredient,
            total: totals.values.sum,
            data: periods.index_with { |period| totals[period].to_f }
          }
        }
        .sort_by { |series| [-series[:total], series[:ingredient].name.to_s.downcase] }
    end

    # "From one location to another": how much moved on each route, kept as a
    # count of items and transfers because quantities across ingredients cannot
    # be added into a single number.
    def build_routes(rows)
      rows
        .group_by { |row| [row.from_location, row.to_location] }
        .map { |(from, to), route_rows|
          {
            from_location: from,
            to_location: to,
            ingredient_count: route_rows.map { |row| row.ingredient.id }.uniq.size,
            transfer_count: route_rows.reduce(Set.new) { |ids, row| ids | row.transfer_ids }.size
          }
        }
        .sort_by { |route| [-route[:ingredient_count], route[:from_location].name.to_s] }
    end

    def periods
      @periods ||= begin
        list = []
        cursor = period_for(@start_date)
        last = period_for(@end_date)
        while cursor <= last
          list << cursor
          cursor = advance(cursor)
        end
        list
      end
    end

    def period_for(date)
      case @granularity
      when "week" then date.beginning_of_week
      when "month" then date.beginning_of_month
      else date
      end
    end

    def advance(period)
      case @granularity
      when "week" then period + 1.week
      when "month" then period + 1.month
      else period + 1.day
      end
    end

    # Explicit strftime rather than the app's :short date format, which carries a
    # time component ("Mar 15 00:00") that means nothing on a date axis.
    #
    # Daily buckets carry the weekday: transfer volume runs on a weekly rhythm, and
    # a bare date makes that unreadable. A week or month bucket spans weekdays, so
    # naming one there would be meaningless.
    def period_label(period)
      case @granularity
      when "month" then I18n.l(period, format: "%B %Y")
      when "week" then week_label(period)
      else I18n.l(period, format: "%a %d %b")
      end
    end

    # Weeks run Saturday to Friday, set app-wide by config.beginning_of_week so
    # payroll, the overtime check and every weekly report agree. The label spells
    # out both ends: a lone start date leaves the reader guessing where it stops.
    def week_label(period)
      finish = period.end_of_week
      start_format = period.month == finish.month ? "%d" : "%d %b"
      "#{I18n.l(period, format: start_format)} – #{I18n.l(finish, format: "%d %b")}"
    end

    # A day-by-day line over a year is unreadable; pick a bucket that fits the
    # range unless the manager asked for a specific one.
    def default_granularity
      days = (@end_date - @start_date).to_i
      return "day" if days <= 45
      return "week" if days <= 400

      "month"
    end
  end
end
