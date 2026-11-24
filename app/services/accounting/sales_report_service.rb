# frozen_string_literal: true

module Accounting
  class SalesReportService
    # Statuses counted when the report is asked to include open orders: placed
    # but not yet completed (most get completed in bulk at drawer close).
    OPEN_STATUSES = Order::PLACED_STATUSES

    # include_open: also count placed orders that are not completed yet, so the
    # report can be read during the day. Off by default — the day close, COGS
    # and every other caller work from completed orders only.
    # location_id: one branch only; nil means every branch. Every section is
    # built from completed_orders, so they all follow it.
    def initialize(start_date, end_date, include_open: false, location_id: nil)
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @include_open = include_open
      @location_id = location_id
    end

    def call
      {
        summary: summary,
        by_category: by_category,
        by_item: by_item,
        by_payment_method: by_payment_method,
        hourly_distribution: hourly_distribution,
        weekday_hour_distribution: weekday_hour_distribution,
        daily_totals: daily_totals,
        daily_order_counts: daily_order_counts
      }
    end

    # Public so the report can fetch just the headline numbers for the
    # previous period (the comparison), without the per-item breakdowns.
    def summary
      @summary ||= build_summary
    end

    private

    # The orders the report counts. A class method so the Order notes page
    # (OrderNotesService) lists notes from exactly the same orders.
    def self.orders_scope(start_date, end_date, include_open: false, location_id: nil)
      statuses = include_open ? %w[completed] + OPEN_STATUSES : %w[completed]
      scope = Order.where(status: statuses).on_business_days(start_date, end_date)
      location_id ? scope.where(location_id: location_id) : scope
    end

    def completed_orders
      @completed_orders ||= self.class.orders_scope(@start_date, @end_date, include_open: @include_open, location_id: @location_id)
    end

    def order_ids
      @order_ids ||= completed_orders.pluck(:id)
    end

    def build_summary
      count = completed_orders.count
      gross = completed_orders.sum(:subtotal_cents).to_i
      discounts = completed_orders.sum(:discount_cents).to_i
      promo_cost = OrderDiscount.promos.where(order_id: order_ids).sum(:amount_cents).to_i
      refunds = RevenueCalculator.refunds_cents(order_ids)
      {
        order_count: count,
        gross_sales_cents: gross,
        discount_cents: discounts,
        promo_cost_cents: promo_cost,
        tax_cents: completed_orders.sum(:tax_cents).to_i,
        tip_cents: completed_orders.sum(:tip_cents).to_i,
        delivery_fee_cents: completed_orders.sum(:delivery_fee_cents).to_i,
        refunds_cents: refunds,
        net_sales_cents: gross - discounts - refunds,
        # Delivery fees are the driver's, not the restaurant's takings.
        average_ticket_cents: count.positive? ? (completed_orders.average(Arel.sql("orders.total_cents - orders.delivery_fee_cents")) || 0).to_i : 0
      }
    end

    def by_category
      rows = Category.order(:position).map do |cat|
        scope = OrderItem.joins(:order, :menu_item)
          .where(orders: { id: order_ids })
          .where(menu_items: { category_id: cat.id })
        category_row(cat.name, scope)
      end

      combo_scope = OrderItem.joins(:order).where(orders: { id: order_ids }).where.not(combo_id: nil)
      combo_row = category_row(I18n.t("accounting.sales_reports.combos_category"), combo_scope)
      rows << combo_row if combo_row[:revenue_cents].positive?

      rows.sort_by { |r| -r[:revenue_cents] }
    end

    # revenue_cents is the menu price (before promos); discount_cents the promo
    # discount on those lines; net_cents what was actually charged for them.
    def category_row(name, scope)
      revenue = RevenueCalculator.order_item_revenue(scope)
      discount = RevenueCalculator.order_item_promo_discount(scope)
      { category: name, units_sold: scope.sum(:quantity).to_i, revenue_cents: revenue,
        discount_cents: discount, net_cents: revenue - discount }
    end

    # One row per menu item or combo (grouped by id, so two items that share a
    # name stay separate), with its category for the items table's filter, and
    # its sales split by modifier choice (see #modifier_breakdown).
    def by_item
      return [] if order_ids.empty?

      combos_label = I18n.t("accounting.sales_reports.combos_category")
      breakdown = modifier_breakdown
      rows = OrderItem.joins("LEFT JOIN menu_items ON menu_items.id = order_items.menu_item_id")
        .joins("LEFT JOIN combos ON combos.id = order_items.combo_id")
        .joins("LEFT JOIN categories ON categories.id = menu_items.category_id")
        .where(order_id: order_ids)
        .group("order_items.menu_item_id", "order_items.combo_id", "menu_items.name", "combos.name", "categories.name", "categories.id")
        .pluck(
          Arel.sql("COALESCE(menu_items.name, combos.name)"),
          Arel.sql("categories.name"),
          Arel.sql("categories.id"),
          Arel.sql("order_items.menu_item_id"),
          Arel.sql("order_items.combo_id"),
          Arel.sql("SUM(order_items.quantity)"),
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_LINE_REVENUE})"),
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_PROMO_DISCOUNT})")
        )

      rows.map do |name, category, category_id, menu_item_id, combo_id, units, revenue, discount|
        units = units.to_i
        revenue = revenue.to_i
        discount = discount.to_i
        {
          name: name,
          # Ids for links (the notes page filters by them); the key is what
          # OrderNotesService uses for an item, menu item or combo alike.
          item_key: OrderNotesService.item_key(menu_item_id, combo_id),
          category_key: OrderNotesService.category_key(category_id, combo_id),
          category: combo_id ? combos_label : category,
          units_sold: units,
          # Menu price before promos, the promo discount, and what was charged.
          revenue_cents: revenue,
          discount_cents: discount,
          net_cents: revenue - discount,
          modifier_groups: modifier_groups_for(breakdown[[menu_item_id, combo_id]], units, revenue, discount)
        }
      end.sort_by { |r| -r[:revenue_cents] }
    end

    # Units and revenue per (item, modifier group, choice). Keyed by the group's
    # and the choice's *names*, so groups that were duplicated on the menu (the
    # same "size" group copied per item) read as one. A choice's revenue is the
    # whole line it was sold on, so a required group adds up to its item.
    def modifier_breakdown
      rows = OrderItem.joins(order_item_modifiers: { modifier: :modifier_group })
        .where(order_id: order_ids)
        .group("order_items.menu_item_id", "order_items.combo_id", "modifier_groups.name", "order_item_modifiers.name")
        .pluck(
          Arel.sql("order_items.menu_item_id"),
          Arel.sql("order_items.combo_id"),
          Arel.sql("modifier_groups.name"),
          Arel.sql("MIN(COALESCE(modifier_groups.position, 0))"),
          Arel.sql("order_item_modifiers.name"),
          Arel.sql("SUM(order_items.quantity)"),
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_LINE_REVENUE})"),
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_PROMO_DISCOUNT})")
        )

      rows.group_by { |menu_item_id, combo_id, *| [menu_item_id, combo_id] }
    end

    # The item's groups, each with its choices (most sold first) and, when some
    # of the item's lines had no choice in that group, a "no choice" row for the
    # rest, so every group adds up to the item row above it.
    def modifier_groups_for(rows, item_units, item_revenue, item_discount)
      return [] if rows.blank?

      rows.group_by { |_, _, group_name, *| group_name }.map do |group_name, choices|
        position = choices.map { |r| r[3].to_i }.min
        list = choices.map do |*, choice, units, revenue, discount|
          revenue = revenue.to_i
          discount = discount.to_i
          { name: choice, units_sold: units.to_i, revenue_cents: revenue, discount_cents: discount, net_cents: revenue - discount }
        end
          .sort_by { |c| [-c[:units_sold], -c[:revenue_cents], c[:name].to_s] }

        rest_units = item_units - list.sum { |c| c[:units_sold] }
        rest_revenue = item_revenue - list.sum { |c| c[:revenue_cents] }
        rest_discount = item_discount - list.sum { |c| c[:discount_cents] }
        if rest_units.positive?
          list << { name: I18n.t("accounting.sales_reports.no_choice"), units_sold: rest_units,
                    revenue_cents: rest_revenue, discount_cents: rest_discount,
                    net_cents: rest_revenue - rest_discount, no_choice: true }
        end

        { name: group_name, position: position, choices: list }
      end.sort_by { |g| [g[:position], g[:name].to_s] }
    end

    def by_payment_method
      Payment.where(order_id: order_ids, status: "completed")
        .group(:payment_method)
        .sum(:amount_cents)
        .transform_values(&:to_i)
    end

    # Per hour of the day (0..23), summed over every day in the range: order
    # count and net sales, the same sales figure as the daily totals.
    def hourly_distribution
      hours = completed_orders.group_by_hour_of_day(:placed_at, time_zone: Time.zone)
      counts = hours.count
      sales = hours.sum(Arel.sql(RevenueCalculator::ORDER_NET_SALES))
      (0..23).to_h { |h| [h, { count: counts.fetch(h, 0), sales_cents: sales.fetch(h, 0).to_i }] }
    end

    # Per weekday and hour, summed over the range: { [wday, hour] => { count:, sales_cents: } }.
    # The weekday is the order's business day (0 = Sunday, as Date#wday), so a
    # 01:00 order after a Thursday night counts on Thursday; the hour is when it
    # was placed, in the app's time zone, as in hourly_distribution. Only cells
    # with orders are present.
    def weekday_hour_distribution
      zone = connection_quote(Time.zone.tzinfo.identifier)
      wday = "EXTRACT(DOW FROM orders.business_date)::int"
      hour = "EXTRACT(HOUR FROM (orders.placed_at AT TIME ZONE 'UTC') AT TIME ZONE #{zone})::int"
      completed_orders.where.not(placed_at: nil)
        .group(Arel.sql(wday), Arel.sql(hour))
        .pluck(Arel.sql(wday), Arel.sql(hour), Arel.sql("COUNT(*)"), Arel.sql("SUM(#{RevenueCalculator::ORDER_NET_SALES})"))
        .to_h { |d, h, count, sales| [[d, h], { count: count.to_i, sales_cents: sales.to_i }] }
    end

    def connection_quote(value) = Order.connection.quote(value)

    # Per business day, every day of the range present (zero when nothing sold).
    def daily_totals
      sums = completed_orders.group(:business_date).sum(Arel.sql(RevenueCalculator::ORDER_NET_SALES))
      (@start_date..@end_date).index_with { |date| sums.fetch(date, 0) }
    end

    # Orders per business day, same days as daily_totals (for the trend table).
    def daily_order_counts
      counts = completed_orders.group(:business_date).count
      (@start_date..@end_date).index_with { |date| counts.fetch(date, 0) }
    end
  end
end
