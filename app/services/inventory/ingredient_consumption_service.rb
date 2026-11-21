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
      completed_orders = Order.where(status: "completed").on_business_days(@start, @end)
      order_ids = completed_orders.select(:id)
      # The item recipes plus the recipes of the modifiers chosen on each line —
      # what stock deduction draws down, so neither shows up as unexplained variance.
      usage = ConsumptionByCombo.new(OrderItem.where(order_id: order_ids)).quantity_by_ingredient

      rows = Ingredient.active.includes(:unit_ref).map do |ingredient|
        theoretical = usage.fetch(ingredient.id, 0).to_d
        actual = ingredient.stock_adjustments
          .where(adjustment_type: "consumption", created_at: range)
          # Netted, not ABS: a voided completed order puts its stock back as a
          # positive consumption row, and that must cancel the draw-down.
          .sum("-quantity_delta")
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
  end
end
