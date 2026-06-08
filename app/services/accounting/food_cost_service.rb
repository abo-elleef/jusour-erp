# frozen_string_literal: true

module Accounting
  class FoodCostService
    def initialize(start_date, end_date)
      @start = start_date
      @end = end_date
    end

    def call
      completed_orders = Order.completed.where(
        created_at: @start.beginning_of_day..@end.end_of_day
      )
      order_ids = completed_orders.select(:id)

      items = MenuItem.available.includes(recipes: :ingredient).filter_map do |item|
        scope = OrderItem.where(order_id: order_ids, menu_item_id: item.id)
        units_sold = scope.sum(:quantity)
        next if units_sold.zero?

        revenue_cents = RevenueCalculator.order_item_revenue(scope)

        ingredient_cost_per_unit = item.recipes.sum do |r|
          (r.quantity_used * r.ingredient.cost_per_unit_cents).round
        end
        total_cost_cents = ingredient_cost_per_unit * units_sold
        food_cost_pct = revenue_cents.positive? ? (total_cost_cents.to_f / revenue_cents * 100).round(1) : 0

        {
          item: item,
          units_sold: units_sold,
          revenue_cents: revenue_cents,
          cost_cents: total_cost_cents,
          food_cost_pct: food_cost_pct
        }
      end

      total_revenue = RevenueCalculator.order_item_revenue(OrderItem.where(order_id: order_ids))
      total_cost = items.sum { |i| i[:cost_cents] }
      overall_pct = total_revenue.positive? ? (total_cost.to_f / total_revenue * 100).round(1) : 0

      {
        items: items.sort_by { |i| -i[:revenue_cents] },
        overall_food_cost_pct: overall_pct,
        total_revenue_cents: total_revenue,
        total_cost_cents: total_cost
      }
    end
  end
end
