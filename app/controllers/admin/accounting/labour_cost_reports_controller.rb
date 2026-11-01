# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Labour cost as a share of sales, by month, company-wide
    # (::Accounting::LabourCostService). One row per month, so no pagination
    # and no sorting: months read in order.
    class LabourCostReportsController < BaseController
      helper_method :print_mode?

      def index
        parse_date_range(default_start: Date.current.beginning_of_year)
        @result = ::Accounting::LabourCostService.new(start_date: @start_date, end_date: @end_date).call

        respond_to do |format|
          format.html
          format.csv do
            send_data "﻿#{report_csv}", filename: "labour-cost-#{@start_date}-#{@end_date}.csv",
                                            type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      def print_mode?
        params[:print].present?
      end

      def report_csv
        CSV.generate do |csv|
          csv << [t("accounting.labour_cost.title"), @start_date.to_s, @end_date.to_s]
          csv << [t("accounting.labour_cost.table.month"), t("accounting.labour_cost.table.revenue"),
                  t("accounting.labour_cost.table.cost"), t("accounting.labour_cost.table.percent"),
                  t("accounting.labour_cost.table.headcount"), t("accounting.labour_cost.table.per_head"),
                  t("accounting.labour_cost.table.status")]
          @result.months.each do |month|
            csv << [month.month.strftime("%Y-%m"), csv_amount(month.revenue_cents), csv_amount(month.cost_cents),
                    month.percent&.round(1), month.headcount, month.cost_per_head_cents && csv_amount(month.cost_per_head_cents),
                    t("accounting.labour_cost.status.#{month.status}")]
          end
          csv << [t("accounting.labour_cost.table.total"), csv_amount(@result.revenue_cents),
                  csv_amount(@result.cost_cents), @result.percent&.round(1)]
        end
      end

      # Plain decimals, not formatted money: the file is opened in a spreadsheet.
      def csv_amount(cents)
        format("%.2f", cents.to_d / 100)
      end
    end
  end
end
