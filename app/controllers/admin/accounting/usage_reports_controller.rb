# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Combined management report: what was sold (menu items) and what it consumed
    # in ingredients (theoretical vs actual), over a date range.
    class UsageReportsController < BaseController
      before_action { require_feature!(:menu) }

      def index
        parse_date_range
        @food_cost = ::Accounting::FoodCostService.new(@start_date, @end_date).call

        consumption = ::Inventory::IngredientConsumptionService.new(@start_date, @end_date).call
        @completed_orders_count = consumption[:completed_orders_count]
        @total_theoretical = consumption[:total_theoretical]
        @total_actual = consumption[:total_actual]
        @consumption_rows = consumption[:rows]
          .select { |row| row[:theoretical].positive? || row[:actual].positive? }
          .sort_by { |row| -row[:theoretical] }

        respond_to do |format|
          format.html
          format.csv do
            send_data usage_csv,
              filename: "sales-consumption-#{@start_date}-#{@end_date}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      def usage_csv
        money = ->(cents) { helpers.format_money(cents) }
        body = CSV.generate do |csv|
          csv << ["Menu items sold", "#{@start_date} to #{@end_date}"]
          csv << ["Item", "Units sold", "Revenue", "Ingredient cost", "Food cost %"]
          @food_cost[:items].each do |row|
            csv << [
              row[:item].name,
              row[:units_sold],
              money.call(row[:revenue_cents]),
              money.call(row[:cost_cents]),
              "#{row[:food_cost_pct]}%"
            ]
          end
          csv << ["Total", "", money.call(@food_cost[:total_revenue_cents]),
                  money.call(@food_cost[:total_cost_cents]), "#{@food_cost[:overall_food_cost_pct]}%"]

          csv << []
          csv << ["Ingredients consumed", "theoretical (from sales) vs actual (from stock)"]
          csv << ["Ingredient", "Unit", "Theoretical", "Actual", "Variance", "Variance %"]
          @consumption_rows.each do |row|
            csv << [
              row[:ingredient].name,
              row[:ingredient].unit,
              row[:theoretical],
              row[:actual],
              row[:variance],
              "#{row[:variance_pct]}%"
            ]
          end
        end
        "﻿#{body}"
      end
    end
  end
end
