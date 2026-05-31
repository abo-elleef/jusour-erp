# frozen_string_literal: true

module Admin
  module Inventory
    class ReportsController < BaseController
      def valuation
        authorize_inventory_index!
        @ingredients = Ingredient.active.includes(:ingredient_category).order("ingredient_categories.name", :name)
        @by_category = @ingredients.group_by(&:ingredient_category)
        @total_cost_value = @ingredients.sum(&:stock_value_cents)
        @ingredient_count = @ingredients.size
        @category_count = @by_category.size

        respond_to do |format|
          format.html
          format.csv { send_data valuation_csv, filename: "valuation-#{Date.current}.csv" }
        end
      end

      def variance
        authorize_inventory_index!
        @start_date = params[:start_date].presence&.to_date || 7.days.ago.to_date
        @end_date = params[:end_date].presence&.to_date || Date.current
        range = @start_date.beginning_of_day..@end_date.end_of_day

        completed_orders = Order.where(status: "completed", created_at: range)
        @completed_orders_count = completed_orders.count
        @variance_rows = Ingredient.active.map do |ingredient|
          theoretical = theoretical_usage(ingredient, completed_orders)
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

        @ingredient_count = @variance_rows.size
        @high_variance_count = @variance_rows.count { |row| row[:variance_pct].abs > 10 }

        respond_to do |format|
          format.html
          format.csv { send_data variance_csv, filename: "variance-#{@start_date}-#{@end_date}.csv" }
        end
      end

      private

      def theoretical_usage(ingredient, orders)
        OrderItem
          .joins(:order, menu_item: :recipes)
          .where(orders: { id: orders.select(:id) })
          .where(recipes: { ingredient_id: ingredient.id })
          .sum("recipes.quantity_used * order_items.quantity")
          .to_d
      end

      def valuation_csv
        build_csv(
          [
            %w[Category Ingredient Unit OnHand CostPerUnitCents StockValueCents],
            *@ingredients.map do |i|
              [i.ingredient_category.name, i.name, i.unit, i.quantity_on_hand, i.cost_per_unit_cents, i.stock_value_cents]
            end,
            [],
            ["Total", "", "", "", "", @total_cost_value]
          ]
        )
      end

      def variance_csv
        build_csv(
          [
            %w[Ingredient Theoretical Actual Variance VariancePct],
            *@variance_rows.map do |row|
              [
                row[:ingredient].name,
                row[:theoretical],
                row[:actual],
                row[:variance],
                row[:variance_pct]
              ]
            end
          ]
        )
      end

      def build_csv(rows)
        rows.map { |row| row.map { |cell| escape_csv_cell(cell) }.join(",") }.join("\n")
      end

      def escape_csv_cell(value)
        str = value.nil? ? "" : value.to_s
        return str unless str.match?(/[",\n\r]/)

        "\"#{str.gsub('"', '""')}\""
      end
    end
  end
end
