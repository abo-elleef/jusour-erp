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

    private

    def completed_orders
      @completed_orders ||= Order.completed.where(created_at: @range)
    end

    def order_ids
      @order_ids ||= completed_orders.pluck(:id)
    end

    def summary
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
        { category: cat.name, revenue_cents: RevenueCalculator.order_item_revenue(scope) }
      end

      combo_scope = OrderItem.joins(:order).where(orders: { id: order_ids }).where.not(combo_id: nil)
      combo_revenue = RevenueCalculator.order_item_revenue(combo_scope)
      if combo_revenue.positive?
        rows << { category: I18n.t("accounting.sales_reports.combos_category"), revenue_cents: combo_revenue }
      end

      rows.sort_by { |r| -r[:revenue_cents] }
    end

    # One row per menu item or combo (grouped by id, so two items that share a
    # name stay separate), with its category for the items table's filter.
    def by_item
      return [] if order_ids.empty?

      combos_label = I18n.t("accounting.sales_reports.combos_category")
      rows = OrderItem.joins("LEFT JOIN menu_items ON menu_items.id = order_items.menu_item_id")
        .joins("LEFT JOIN combos ON combos.id = order_items.combo_id")
        .joins("LEFT JOIN categories ON categories.id = menu_items.category_id")
        .where(order_id: order_ids)
        .group("order_items.menu_item_id", "order_items.combo_id", "menu_items.name", "combos.name", "categories.name")
        .pluck(
          Arel.sql("COALESCE(menu_items.name, combos.name)"),
          Arel.sql("categories.name"),
          Arel.sql("order_items.combo_id"),
          Arel.sql("SUM(order_items.quantity)"),
          Arel.sql("SUM(#{RevenueCalculator::ORDER_ITEM_LINE_REVENUE})")
        )

      rows.map do |name, category, combo_id, units, revenue|
        { name: name, category: combo_id ? combos_label : category, units_sold: units.to_i, revenue_cents: revenue.to_i }
      end.sort_by { |r| -r[:revenue_cents] }
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
