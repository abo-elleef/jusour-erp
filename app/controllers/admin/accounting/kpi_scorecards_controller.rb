# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Six months of KPIs side by side (::Accounting::KpiScorecardService). The
    # period is picked by its last month — the last complete month by default,
    # since the current one is still filling up.
    class KpiScorecardsController < BaseController
      helper_method :print_mode?

      # [key, unit, group]. Restaurant ratios show only for restaurants; days to
      # collect only where the company sells on credit (elsewhere it is 0 by
      # definition and the cash cycle counts it as such).
      ROWS = [
        [:revenue, :amount, :profitability],
        [:gross_margin, :percent, :profitability],
        [:net_margin, :percent, :profitability],
        [:food_cost, :percent, :restaurant],
        [:labour_percent, :percent, :restaurant],
        [:prime_cost, :percent, :restaurant],
        [:dso, :days, :working_capital],
        [:dpo, :days, :working_capital],
        [:inventory_days, :days, :working_capital],
        [:cash_cycle, :days, :working_capital]
      ].freeze

      def show
        @end_month = parse_end_month
        @months = ::Accounting::KpiScorecardService.new(end_month: @end_month).call.reverse
        @rows = visible_rows

        respond_to do |format|
          format.html
          format.csv do
            send_data "﻿#{scorecard_csv}", filename: "kpi-scorecard-#{@end_month.strftime('%Y-%m')}.csv",
                                               type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      def print_mode?
        params[:print].present?
      end

      def parse_end_month
        Date.strptime(params[:month].to_s, "%Y-%m")
      rescue ArgumentError
        Date.current.prev_month.beginning_of_month
      end

      def visible_rows
        ROWS.reject do |key, _, group|
          (group == :restaurant && !Current.company&.restaurant?) ||
            (key == :dso && !Current.company&.feature_enabled?(:ar_credit_sales))
        end
      end

      def scorecard_csv
        CSV.generate do |csv|
          csv << [t("accounting.kpi.title"), *@months.map { |m| m.month.strftime("%Y-%m") }]
          @rows.each do |key, unit, _|
            csv << [t("accounting.kpi.rows.#{key}"), *@months.map { |m| csv_value(m.public_send(key), unit) }]
          end
        end
      end

      def csv_value(value, unit)
        return nil if value.nil?

        unit == :amount ? format("%.2f", value.to_d / 100) : value.round(1)
      end
    end
  end
end
