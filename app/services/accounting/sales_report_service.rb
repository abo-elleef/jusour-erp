# frozen_string_literal: true

module Accounting
  class SalesReportService
    def initialize(start_date, end_date)
      @range = BusinessDay.range_between(start_date, end_date)
    end

    def call
      {
        summary: summary,
        by_category: by_category,
        by_item: by_item,
        by_payment_method: by_payment_method,
        hourly_distribution: hourly_distribution,
        daily_totals: daily_totals
      }
    end

    # Public so the report can fetch just the headline numbers for the
    # previous period (the comparison), without the per-item breakdowns.
    def summary
      @summary ||= build_summary
    end

    private

    def completed_orders
      @completed_orders ||= Order.completed.where(created_at: @range)
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
        { category: cat.name, units_sold: scope.sum(:quantity).to_i, revenue_cents: RevenueCalculator.order_item_revenue(scope) }
      end

      combo_scope = OrderItem.joins(:order).where(orders: { id: order_ids }).where.not(combo_id: nil)
      combo_revenue = RevenueCalculator.order_item_revenue(combo_scope)
      if combo_revenue.positive?
        rows << { category: I18n.t("accounting.sales_reports.combos_category"),
                  units_sold: combo_scope.sum(:quantity).to_i, revenue_cents: combo_revenue }
      end

      rows.sort_by { |r| -r[:revenue_cents] }
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
        .group("order_items.menu_item_id", "order_items.combo_id", "menu_items.name", "combos.name", "categories.name")
        .pluck(
          Arel.sql("COALESCE(menu_items.name, combos.name)"),
          Arel.sql("categories.name"),
          Arel.sql("order_items.menu_item_id"),
          Arel.sql("order_items.combo_id"),
          Arel.sql("SUM(order_items.quantity)"),
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_LINE_REVENUE})")
        )

      rows.map do |name, category, menu_item_id, combo_id, units, revenue|
        units = units.to_i
        revenue = revenue.to_i
        {
          name: name,
          category: combo_id ? combos_label : category,
          units_sold: units,
          revenue_cents: revenue,
          modifier_groups: modifier_groups_for(breakdown[[menu_item_id, combo_id]], units, revenue)
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
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_LINE_REVENUE})")
        )

      rows.group_by { |menu_item_id, combo_id, *| [menu_item_id, combo_id] }
    end

    # The item's groups, each with its choices (most sold first) and, when some
    # of the item's lines had no choice in that group, a "no choice" row for the
    # rest, so every group adds up to the item row above it.
    def modifier_groups_for(rows, item_units, item_revenue)
      return [] if rows.blank?

      rows.group_by { |_, _, group_name, *| group_name }.map do |group_name, choices|
        position = choices.map { |r| r[3].to_i }.min
        list = choices.map { |*, choice, units, revenue| { name: choice, units_sold: units.to_i, revenue_cents: revenue.to_i } }
          .sort_by { |c| [-c[:units_sold], -c[:revenue_cents], c[:name].to_s] }

        rest_units = item_units - list.sum { |c| c[:units_sold] }
        rest_revenue = item_revenue - list.sum { |c| c[:revenue_cents] }
        if rest_units.positive?
          list << { name: I18n.t("accounting.sales_reports.no_choice"), units_sold: rest_units,
                    revenue_cents: rest_revenue, no_choice: true }
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

    def hourly_distribution
      completed_orders.group_by_hour(:created_at, time_zone: Time.zone, range: @range).count
    end

    def daily_totals
      completed_orders
        .group_by_day(:created_at, time_zone: Time.zone, day_start: BusinessDay.start_hour, range: @range)
        .sum(Arel.sql(RevenueCalculator::ORDER_NET_SALES))
    end
  end
end
