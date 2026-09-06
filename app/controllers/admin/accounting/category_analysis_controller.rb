# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Expense and income by category over a date range — what each category cost
    # or earned, its share of that side, and how it moved over time.
    class CategoryAnalysisController < BaseController
      def index
        parse_date_range(default_start: 30.days.ago.to_date)

        @kind = params[:kind].presence_in(::Accounting::CategoryAnalysisService::KINDS) || "both"
        @category_ids = Array(params[:category_ids]).compact_blank
        @granularity = params[:granularity]

        @analysis = ::Accounting::CategoryAnalysisService.new(
          start_date: @start_date,
          end_date: @end_date,
          kind: @kind,
          category_ids: @category_ids,
          granularity: @granularity
        ).call

        respond_to do |format|
          format.html
          format.csv do
            send_data analysis_csv,
              filename: "category-analysis-#{@start_date}-#{@end_date}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      def analysis_csv
        CSV.generate do |csv|
          csv << ["Category analysis", "#{@start_date} to #{@end_date}"]
          csv << ["Type", "Category", "Entries", "Total", "Share %", "Average"] + @analysis.period_labels
          @analysis.rows.each do |row|
            csv << [
              row.kind.to_s,
              row.category.name,
              row.entry_count,
              helpers.format_money(row.total_cents),
              row.share_pct,
              helpers.format_money(row.average_cents)
            ] + @analysis.periods.map { |period| helpers.format_money(row.amounts[period] || 0) }
          end
          csv << []
          csv << ["Total expense", helpers.format_money(@analysis.expense_cents)]
          csv << ["Total income", helpers.format_money(@analysis.income_cents)]
          csv << ["Net", helpers.format_money(@analysis.net_cents)]
        end
      end
    end
  end
end
