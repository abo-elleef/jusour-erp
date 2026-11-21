# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class SalesReportsController < BaseController
      before_action { require_feature!(:menu) }

      def index
        parse_date_range
        @include_open = params[:include_open] == "1"
        # Only branches sell; inactive ones stay so their past sales can be read.
        @locations = Location.branches.ordered
        @location = @locations.find_by(id: params[:location_id]) if params[:location_id].present?
        @report = ::Accounting::SalesReportService.new(@start_date, @end_date, include_open: @include_open, location_id: @location&.id).call
        prepare_items
        prepare_comparison
        prepare_orders_by_hour

        respond_to do |format|
          format.html { prepare_note_counts }
          format.csv { send_data generate_sales_csv, filename: "sales-#{@start_date}-#{@end_date}.csv" }
          format.pdf do
            send_data ::Accounting::PdfReportService.new(@report, @start_date, @end_date, one_branch: @location.present?).render,
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
        "revenue"  => ->(r) { r[:revenue_cents] },
        "discount" => ->(r) { r[:discount_cents] },
        "net"      => ->(r) { r[:net_cents] }
      }.freeze

      ITEMS_PREVIEW = 10

      # The items table: optional category filter, sortable columns (whitelisted
      # — the key comes from the URL), and each item's share of net item sales
      # (after promo discounts), so a promo'd item is not overstated.
      def prepare_items
        all_items = @report[:by_item]
        @item_categories = all_items.filter_map { |r| r[:category] }.uniq.sort_by(&:downcase)
        @item_category = params[:item_category] if @item_categories.include?(params[:item_category])
        @item_sort = ITEM_SORTS.key?(params[:sort]) ? params[:sort] : "net"
        @item_dir = params[:dir] == "asc" ? "asc" : "desc"

        items = @item_category ? all_items.select { |r| r[:category] == @item_category } : all_items
        @item_total_cents = items.sum { |r| r[:net_cents] }
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
            category_key: rows.first[:category_key],
            units_sold: rows.sum { |r| r[:units_sold] },
            revenue_cents: rows.sum { |r| r[:revenue_cents] },
            discount_cents: rows.sum { |r| r[:discount_cents] },
            net_cents: rows.sum { |r| r[:net_cents] },
            items: @item_dir == "asc" ? sorted : sorted.reverse
          }
        end
        group_sort = @item_sort == "category" ? "name" : @item_sort
        sorted = groups.sort_by { |g| [ITEM_SORTS[group_sort].call(g), g[:name].to_s.downcase] }
        @item_dir == "asc" ? sorted : sorted.reverse
      end

      # How many order notes sit behind each category / item / choice row, for the
      # chips that open the Order notes page already filtered to that row.
      def prepare_note_counts
        @note_counts = ::Accounting::OrderNotesService.new(@start_date, @end_date, include_open: @include_open, location_id: @location&.id).counts
        @notes_params = { start_date: @start_date, end_date: @end_date, location_id: @location&.id, include_open: (@include_open ? "1" : nil) }.compact
      end

      # Headline numbers for the period of the same length just before this one,
      # so each card can say whether it went up or down.
      def prepare_comparison
        days = (@end_date - @start_date).to_i + 1
        @previous_end = @start_date - 1
        @previous_start = @previous_end - (days - 1)
        @previous = ::Accounting::SalesReportService.new(@previous_start, @previous_end, include_open: @include_open, location_id: @location&.id).summary
      end

      # Orders and sales per hour of the day, summed over every day in the range,
      # in business-day order (so a day that starts at 06:00 reads 06:00 → 05:00).
      # share_percent: the hour's part of the period's sales.
      def prepare_orders_by_hour
        hours = @report[:hourly_distribution]
        total = hours.values.sum { |h| h[:sales_cents] }
        start = BusinessDay.start_hour.to_i
        @orders_by_hour = (0..23).map { |i| (start + i) % 24 }.map do |hour|
          h = hours[hour]
          {
            hour: hour,
            count: h[:count],
            sales_cents: h[:sales_cents],
            share_percent: total.positive? ? (h[:sales_cents] * 100.0 / total).round(1) : 0
          }
        end
      end

      def generate_sales_csv
        summary = @report[:summary]
        CSV.generate(headers: true) do |csv|
          csv << %w[Metric Value]
          csv << ["Branch", @location&.name || "All branches"]
          csv << ["Gross Sales", helpers.format_money(summary[:gross_sales_cents])]
          csv << ["Discounts", helpers.format_money(summary[:discount_cents])]
          csv << ["Tax", helpers.format_money(summary[:tax_cents])]
          csv << ["Tips", helpers.format_money(summary[:tip_cents])]
          csv << ["Net Sales", helpers.format_money(summary[:net_sales_cents])]
          csv << []
          csv << ["Category", "Units sold", "Revenue before discount", "Promo discount", "Net revenue"]
          @report[:by_category].each { |r| csv << [r[:category], r[:units_sold], *revenue_cells(r)] }
          csv << []
          csv << ["Item", "Category", "Units sold", "Revenue before discount", "Promo discount", "Net revenue"]
          @items.each { |r| csv << [r[:name], r[:category], r[:units_sold], *revenue_cells(r)] }
          if @items.any? { |r| r[:modifier_groups].present? }
            csv << []
            csv << ["Item", "Modifier group", "Choice", "Units sold", "Revenue before discount", "Promo discount", "Net revenue"]
            @items.each do |r|
              r[:modifier_groups].each do |group|
                group[:choices].each do |choice|
                  csv << [r[:name], group[:name], choice[:name], choice[:units_sold], *revenue_cells(choice)]
                end
              end
            end
          end
          csv << []
          csv << %w[Payment\ Method Total]
          @report[:by_payment_method].each { |method, cents| csv << [method.titleize, helpers.format_money(cents)] }
        end
      end

      def revenue_cells(row)
        [row[:revenue_cents], row[:discount_cents], row[:net_cents]].map { |cents| helpers.format_money(cents) }
      end
    end
  end
end
