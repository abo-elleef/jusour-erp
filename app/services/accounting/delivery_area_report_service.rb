# frozen_string_literal: true

module Accounting
  # Delivery orders per delivery area: how many, the fees charged and the food
  # sold, for a date range and branch. Reads the same orders as the Sales report
  # (SalesReportService.orders_scope: completed, plus open when asked, by business
  # date — never voided, cancelled or draft), narrowed to delivery orders.
  #
  # The area is what the cashier picked (or the online customer chose); the fee
  # is what the order was actually charged, which may differ from the area's
  # price. Delivery orders with no area get one "No area" row. Active areas with
  # no orders are listed with zeros, so quiet areas show up too.
  class DeliveryAreaReportService
    SORTS = %w[name branch orders share fees avg_fee food avg_food].freeze

    Row = Struct.new(:area, :location, :orders, :fee_cents, :food_cents, keyword_init: true) do
      def no_area? = area.nil?
      def avg_fee_cents = orders.zero? ? 0 : (fee_cents.to_f / orders).round
      def avg_food_cents = orders.zero? ? 0 : (food_cents.to_f / orders).round
    end

    def initialize(start_date, end_date, location_id: nil, include_open: false)
      @start_date = start_date
      @end_date = end_date
      @location_id = location_id
      @include_open = include_open
    end

    def delivery_orders
      SalesReportService.orders_scope(@start_date, @end_date, include_open: @include_open, location_id: @location_id)
                        .where(order_type: "delivery")
    end

    # [rows, totals]. Totals cover every delivery order in range, area or not.
    def rows(sort: "orders", direction: "desc")
      stats = delivery_orders.group(:delivery_area_id).pluck(
        :delivery_area_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(delivery_fee_cents), 0)"),
        Arel.sql("COALESCE(SUM(COALESCE(subtotal_cents, 0) - COALESCE(discount_cents, 0)), 0)")
      ).index_by(&:first)

      areas = DeliveryArea.where(id: stats.keys.compact).or(zero_order_areas).includes(:location).to_a
      rows = areas.map do |area|
        _, count, fees, food = stats[area.id] || [nil, 0, 0, 0]
        Row.new(area: area, location: area.location, orders: count.to_i, fee_cents: fees.to_i, food_cents: food.to_i)
      end
      if (no_area = stats[nil])
        _, count, fees, food = no_area
        rows << Row.new(area: nil, location: nil, orders: count.to_i, fee_cents: fees.to_i, food_cents: food.to_i)
      end

      totals = Row.new(area: nil, location: nil, orders: rows.sum(&:orders),
                       fee_cents: rows.sum(&:fee_cents), food_cents: rows.sum(&:food_cents))
      [sorted(rows, sort, direction), totals]
    end

    CHART_METRICS = %w[orders fees].freeze
    CHART_TOP = 10

    # Bars for the chart above the table: the top areas by the metric, every
    # other area with orders in one "other" bar, and "No area" last. Each entry is
    # { label:, value:, kind: :area | :other | :no_area, count: (areas in :other) }.
    # Areas with nothing are left out: 50 empty bars say nothing.
    def chart_bars(rows, metric: "orders", top: CHART_TOP)
      value = ->(r) { metric == "fees" ? r.fee_cents / 100.0 : r.orders }
      named = rows.select { |r| r.area && r.orders.positive? }
                  .sort_by { |r| [-value.call(r), r.area.display_name.to_s.downcase] }
      top_rows = named.first(top)
      with_branch = top_rows.map { |r| r.area.location_id }.uniq.size > 1
      bars = top_rows.map { |r| { label: chart_label(r, with_branch), value: value.call(r), kind: :area } }
      rest = named.drop(top)
      if rest.any?
        bars << { label: nil, value: rest.sum { |r| value.call(r) }, kind: :other, count: rest.size }
      end
      if (none = rows.find(&:no_area?)) && none.orders.positive?
        bars << { label: nil, value: value.call(none), kind: :no_area }
      end
      bars
    end

    private

    # Two branches may both have a "Dokki": add the branch when the bars mix branches.
    def chart_label(row, with_branch)
      with_branch ? "#{row.area.display_name} · #{row.location&.name}" : row.area.display_name
    end

    def zero_order_areas
      scope = DeliveryArea.active
      @location_id ? scope.where(location_id: @location_id) : scope
    end

    # "No area" always sits last, whatever the sort, so it never hides among areas.
    def sorted(rows, sort, direction)
      sort = SORTS.include?(sort) ? sort : "orders"
      key = lambda do |r|
        case sort
        when "name" then r.area.display_name.to_s.downcase
        when "branch" then r.location&.name.to_s.downcase
        when "orders", "share" then r.orders
        when "fees" then r.fee_cents
        when "avg_fee" then r.avg_fee_cents
        when "food" then r.food_cents
        when "avg_food" then r.avg_food_cents
        end
      end
      named, unnamed = rows.partition { |r| r.area }
      # Ties always read A→Z, whichever way the column is sorted.
      sign = direction == "desc" ? -1 : 1
      named = named.sort do |a, b|
        cmp = (key.call(a) <=> key.call(b)) * sign
        cmp.zero? ? a.area.display_name.to_s.downcase <=> b.area.display_name.to_s.downcase : cmp
      end
      named + unnamed
    end
  end
end
