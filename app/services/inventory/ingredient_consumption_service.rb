# frozen_string_literal: true

module Inventory
  # Per-ingredient consumption over a date range, comparing what the sales
  # *should* have used (theoretical, from recipes × units sold on completed
  # orders) against what physically left inventory (actual, from "consumption"
  # stock adjustments). Shared by the Variance report and the Sales & Consumption
  # report so both always agree.
  class IngredientConsumptionService
    def initialize(start_date, end_date)
      @start = start_date
      @end = end_date
    end

    def call
      range = @start.beginning_of_day..@end.end_of_day
      completed_orders = Order.where(status: "completed", created_at: range)
      order_ids = completed_orders.select(:id)

      rows = Ingredient.active.includes(:unit_ref).map do |ingredient|
        theoretical = theoretical_usage(ingredient, order_ids)
        actual = ingredient.stock_adjustments
          .where(adjustment_type: "consumption", created_at: range)
          .sum("ABS(quantity_delta)")
          .to_d
        variance = actual - theoretical
        variance_pct = theoretical.positive? ? ((variance / theoretical) * 100).round(1) : 0

        {
          ingredient: ingredient,
          theoretical: theoretical,
          actual: actual,
          variance: variance,
          variance_pct: variance_pct
        }
      end

      {
        rows: rows,
        completed_orders_count: completed_orders.count,
        total_theoretical: rows.sum { |r| r[:theoretical] },
        total_actual: rows.sum { |r| r[:actual] }
      }
    end

    private

    def theoretical_usage(ingredient, order_ids)
      OrderItem
        .joins(:order, menu_item: :recipes)
        .where(orders: { id: order_ids })
        .where(recipes: { ingredient_id: ingredient.id })
        .sum("recipes.quantity_used * order_items.quantity")
        .to_d
    end
  end
end
