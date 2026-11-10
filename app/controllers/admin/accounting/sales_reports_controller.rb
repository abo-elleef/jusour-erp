# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class SalesReportsController < BaseController
      before_action { require_feature!(:menu) }

      def index
        parse_date_range
        @report = ::Accounting::SalesReportService.new(@start_date, @end_date).call
        prepare_items
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

      ITEM_SORTS = {
        "name"     => ->(r) { r[:name].to_s.downcase },
        "category" => ->(r) { r[:category].to_s.downcase },
        "units"    => ->(r) { r[:units_sold] },
        "revenue"  => ->(r) { r[:revenue_cents] }
      }.freeze

      # The items table: optional category filter, sortable columns (whitelisted
      # — the key comes from the URL), and each item's share of item revenue.
      def prepare_items
        all_items = @report[:by_item]
        @item_categories = all_items.filter_map { |r| r[:category] }.uniq.sort_by(&:downcase)
        @item_category = params[:item_category] if @item_categories.include?(params[:item_category])
        @item_sort = ITEM_SORTS.key?(params[:sort]) ? params[:sort] : "revenue"
        @item_dir = params[:dir] == "asc" ? "asc" : "desc"

        items = @item_category ? all_items.select { |r| r[:category] == @item_category } : all_items
        @item_total_cents = items.sum { |r| r[:revenue_cents] }
        sorted = items.sort_by { |r| [ITEM_SORTS[@item_sort].call(r), r[:name].to_s.downcase] }
        @items = @item_dir == "asc" ? sorted : sorted.reverse
      end

      def generate_sales_csv
        summary = @report[:summary]
        CSV.generate(headers: true) do |csv|
          csv << %w[Metric Value]
          csv << ["Gross Sales", helpers.format_money(summary[:gross_sales_cents])]
          csv << ["Discounts", helpers.format_money(summary[:discount_cents])]
          csv << ["Tax", helpers.format_money(summary[:tax_cents])]
          csv << ["Tips", helpers.format_money(summary[:tip_cents])]
          csv << ["Net Sales", helpers.format_money(summary[:net_sales_cents])]
          csv << []
          csv << %w[Category Revenue]
          @report[:by_category].each { |r| csv << [r[:category], helpers.format_money(r[:revenue_cents])] }
          csv << []
          csv << ["Item", "Category", "Units sold", "Revenue"]
          @items.each { |r| csv << [r[:name], r[:category], r[:units_sold], helpers.format_money(r[:revenue_cents])] }
          csv << []
          csv << %w[Payment\ Method Total]
          @report[:by_payment_method].each { |method, cents| csv << [method.titleize, helpers.format_money(cents)] }
        end
      end
    end
  end
end
