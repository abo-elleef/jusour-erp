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
        prepare_comparison
        prepare_orders_by_hour

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

      ITEMS_PREVIEW = 10

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
        # The page shows the top rows unless asked for all; the CSV always has all.
        @show_all_items = params[:all_items] == "1" || @items.size <= ITEMS_PREVIEW
        @visible_items = @show_all_items ? @items : @items.first(ITEMS_PREVIEW)

        # The category filter belongs to the flat list, so a filter means flat.
        @item_view = params[:view] == "flat" || @item_category ? "flat" : "grouped"
        @category_groups = build_category_groups(all_items) if @item_view == "grouped"
      end

      # Grouped view: one row per category with its units and revenue, and its
      # items under it. Built from the item rows, so a category always adds up
      # to the items shown beneath it (items with no category get their own group).
      # Groups and their items follow the same sort as the flat list.
      def build_category_groups(all_items)
        groups = all_items.group_by { |r| r[:category] }.map do |category, rows|
          sorted = rows.sort_by { |r| [ITEM_SORTS[@item_sort].call(r), r[:name].to_s.downcase] }
          {
            name: category || t("accounting.sales_reports.uncategorized"),
            category: category,
            units_sold: rows.sum { |r| r[:units_sold] },
            revenue_cents: rows.sum { |r| r[:revenue_cents] },
            items: @item_dir == "asc" ? sorted : sorted.reverse
          }
        end
        group_sort = @item_sort == "category" ? "name" : @item_sort
        sorted = groups.sort_by { |g| [ITEM_SORTS[group_sort].call(g), g[:name].to_s.downcase] }
        @item_dir == "asc" ? sorted : sorted.reverse
      end

      # Headline numbers for the period of the same length just before this one,
      # so each card can say whether it went up or down.
      def prepare_comparison
        days = (@end_date - @start_date).to_i + 1
        @previous_end = @start_date - 1
        @previous_start = @previous_end - (days - 1)
        @previous = ::Accounting::SalesReportService.new(@previous_start, @previous_end).summary
      end

      # Order count per hour of the day, summed over every day in the range, in
      # business-day order (so a day that starts at 06:00 reads 06:00 → 05:00).
      def prepare_orders_by_hour
        counts = Hash.new(0)
        @report[:hourly_distribution].each { |time, count| counts[time.hour] += count }
        start = BusinessDay.start_hour.to_i
        @orders_by_hour = (0..23).map { |i| (start + i) % 24 }
          .to_h { |hour| [format("%02d:00", hour), counts[hour]] }
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
          csv << ["Category", "Units sold", "Revenue"]
          @report[:by_category].each { |r| csv << [r[:category], r[:units_sold], helpers.format_money(r[:revenue_cents])] }
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
