# frozen_string_literal: true

module Accounting
  # The menu engineering matrix (Kasavana & Smith): every menu item sold in the
  # range placed by how popular it is and how much it earns per plate.
  #
  #   popular   = its share of units sold ≥ 70% of an equal share (0.7 ÷ items)
  #   profitable = its margin per unit ≥ the menu's average margin per unit,
  #                weighted by units sold
  #
  #   Star      popular, profitable      keep it as it is, give it the best spot
  #   Plowhorse popular, low margin      raise the price a little or cut its cost
  #   Puzzle    unpopular, profitable    promote it, rename it, move it up the menu
  #   Dog       unpopular, low margin    rework it or take it off the menu
  #
  # Sales are the same completed orders the Food cost report reads. An item's
  # sales are its lines' price plus chosen modifiers, minus the promo discount
  # booked on that line; order-wide discounts belong to no item and are left out.
  # Cost is the recipe at standard cost, modifier recipes included
  # (Inventory::ConsumptionByCombo), so it agrees with Food cost.
  #
  # An item with no recipe cost has no real margin: it is listed but kept out of
  # the matrix and out of both thresholds, so it cannot drag the averages.
  # Combo lines carry no recipe and are skipped, as the Food cost report does.
  #
  # Classifying within a category (mains against mains) is the usual practice, so
  # the category filter narrows the set the thresholds are computed over.
  class MenuEngineeringService
    CLASSES = %w[star plowhorse puzzle dog].freeze
    NO_COST = "no_cost"
    POPULARITY_FACTOR = 0.7
    SORTS = %w[name category units mix avg_price unit_cost unit_margin total_margin food_cost_pct].freeze

    Row = Struct.new(:menu_item_id, :name, :category_id, :category_name, :units, :sales_cents, :cost_cents,
                     :mix_pct, :klass, keyword_init: true) do
      def avg_price_cents = units.positive? ? (sales_cents / units).round : 0
      def unit_cost_cents = units.positive? ? (cost_cents / units).round : 0
      def margin_cents = sales_cents - cost_cents
      def unit_margin_cents = units.positive? ? (margin_cents / units).round : 0
      def food_cost_pct = sales_cents.positive? ? (100.0 * cost_cents / sales_cents).round(1) : 0.0
      def costed? = cost_cents.positive?
    end

    Result = Struct.new(:rows, :popularity_threshold_pct, :avg_unit_margin_cents, :counts, :totals, keyword_init: true)

    def initialize(start_date, end_date, location_id: nil, category_id: nil)
      @start = start_date
      @end = end_date
      @location_id = location_id
      @category_id = category_id
    end

    # klass: one of CLASSES or NO_COST narrows the rows shown; the thresholds and
    # counts always cover every item in the filter, so the chips stay stable.
    def call(sort: "total_margin", direction: "desc", klass: nil)
      rows = build_rows
      costed = rows.select(&:costed?)
      total_units = costed.sum(&:units)
      threshold_pct = costed.empty? ? 0.0 : (100.0 * POPULARITY_FACTOR / costed.size)
      avg_margin = total_units.positive? ? costed.sum(&:margin_cents).to_d / total_units : 0

      rows.each do |row|
        row.mix_pct = row.costed? && total_units.positive? ? (100.0 * row.units / total_units) : nil
        row.klass = row.costed? ? classify(row, threshold_pct, avg_margin) : NO_COST
      end

      counts = (CLASSES + [NO_COST]).index_with { |k| rows.count { |r| r.klass == k } }
      shown = klass ? rows.select { |r| r.klass == klass } : rows

      Result.new(
        rows: sort_rows(shown, sort, direction),
        popularity_threshold_pct: threshold_pct,
        avg_unit_margin_cents: avg_margin.round.to_i,
        counts: counts,
        totals: totals_for(shown)
      )
    end

    private

    def classify(row, threshold_pct, avg_margin)
      popular = row.mix_pct >= threshold_pct
      profitable = row.unit_margin_cents >= avg_margin
      if popular
        profitable ? "star" : "plowhorse"
      else
        profitable ? "puzzle" : "dog"
      end
    end

    def build_rows
      lines = order_items
      sales = lines.group(:menu_item_id).pluck(
        :menu_item_id,
        Arel.sql("SUM(order_items.quantity)"),
        Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_LINE_REVENUE} - #{RevenueCalculator::ORDER_ITEM_PROMO_DISCOUNT})")
      )
      return [] if sales.empty?

      cost = ::Inventory::ConsumptionByCombo.new(lines).cost_cents_by_menu_item
      items = MenuItem.where(id: sales.map(&:first)).includes(:category).index_by(&:id)

      sales.filter_map do |menu_item_id, units, sales_cents|
        item = items[menu_item_id]
        next if item.nil? || units.to_i.zero?

        Row.new(menu_item_id: menu_item_id, name: item.name, category_id: item.category_id,
                category_name: item.category&.name, units: units.to_i, sales_cents: sales_cents.to_i,
                cost_cents: cost.fetch(menu_item_id, 0).to_i)
      end
    end

    def order_items
      orders = Order.completed.on_business_days(@start, @end)
      orders = orders.where(location_id: @location_id) if @location_id
      scope = OrderItem.where(order_id: orders.select(:id)).where.not(menu_item_id: nil)
      scope = scope.where(menu_item_id: MenuItem.where(category_id: @category_id).select(:id)) if @category_id
      scope
    end

    def totals_for(rows)
      units = rows.sum(&:units)
      sales = rows.sum(&:sales_cents)
      cost = rows.sum(&:cost_cents)
      { units: units, sales_cents: sales, cost_cents: cost, margin_cents: sales - cost,
        food_cost_pct: sales.positive? ? (100.0 * cost / sales).round(1) : 0.0 }
    end

    SORT_VALUES = {
      "name" => ->(r) { r.name.to_s.downcase },
      "category" => ->(r) { [r.category_name.to_s.downcase, r.name.to_s.downcase] },
      "units" => :units.to_proc,
      "mix" => ->(r) { r.mix_pct || -1 },
      "avg_price" => :avg_price_cents.to_proc,
      "unit_cost" => :unit_cost_cents.to_proc,
      "unit_margin" => :unit_margin_cents.to_proc,
      "total_margin" => :margin_cents.to_proc,
      "food_cost_pct" => :food_cost_pct.to_proc
    }.freeze
    private_constant :SORT_VALUES

    def sort_rows(rows, sort, direction)
      key = SORT_VALUES.fetch(SORTS.include?(sort) ? sort : "total_margin")
      sorted = rows.sort_by { |r| [key.call(r), r.name.to_s] }
      direction == "asc" ? sorted : sorted.reverse
    end
  end
end
