# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class SalesReportsController < BaseController
      def index
        parse_date_range
        @report = ::Accounting::SalesReportService.new(@start_date, @end_date).call
        @pnl = ::Accounting::PnlService.new(@start_date, @end_date).call

        respond_to do |format|
          format.html
          format.csv { send_data generate_sales_csv, filename: "sales-#{@start_date}-#{@end_date}.csv" }
          format.pdf do
            send_data ::Accounting::PdfReportService.new(@report, @start_date, @end_date).render,
              filename: "sales-#{@start_date}-#{@end_date}.pdf",
              type: "application/pdf",
              disposition: "attachment"
          end
        end
      end

      private

      def generate_sales_csv
        summary = @report[:summary]
        CSV.generate(headers: true) do |csv|
          csv << %w[Metric Value]
          csv << ["Gross Sales", format_money(summary[:gross_sales_cents])]
          csv << ["Discounts", format_money(summary[:discount_cents])]
          csv << ["Tax", format_money(summary[:tax_cents])]
          csv << ["Tips", format_money(summary[:tip_cents])]
          csv << ["Net Sales", format_money(summary[:net_sales_cents])]
          csv << []
          csv << %w[Category Revenue]
          @report[:by_category].each { |r| csv << [r[:category], format_money(r[:revenue_cents])] }
          csv << []
          csv << %w[Payment\ Method Total]
          @report[:by_payment_method].each { |method, cents| csv << [method.titleize, format_money(cents)] }
        end
      end
    end
  end
end
