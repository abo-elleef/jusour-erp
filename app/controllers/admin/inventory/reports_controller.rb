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
        parse_date_range

        result = ::Inventory::IngredientConsumptionService.new(@start_date, @end_date).call
        @completed_orders_count = result[:completed_orders_count]
        @variance_rows = result[:rows]
        @ingredient_count = @variance_rows.size
        @high_variance_count = @variance_rows.count { |row| row[:variance_pct].abs > 10 }

        respond_to do |format|
          format.html
          format.csv { send_data variance_csv, filename: "variance-#{@start_date}-#{@end_date}.csv" }
        end
      end

      private

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
