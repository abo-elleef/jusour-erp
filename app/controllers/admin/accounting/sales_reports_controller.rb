# frozen_string_literal: true

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
        prepare_weekday_heatmap

        respond_to do |format|
          format.html { prepare_note_counts }
          format.csv do
            send_data ::Accounting::SalesReportCsv.new(**export_args).render,
              filename: "sales-#{@start_date}-#{@end_date}.csv", type: "text/csv; charset=utf-8"
          end
          format.pdf do
            send_data sales_pdf.render,
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

      # Hour × weekday grid for the trend card. Rows run Saturday → Friday (the
      # app's week); columns are the hours in business-day order, trimmed to the
      # first and last hour that had any order. Each cell is the average per
      # day: the total divided by how many of that weekday the range holds, so a
      # range with three Fridays and two Saturdays still compares fairly.
      WEEKDAYS_SAT_FIRST = [6, 0, 1, 2, 3, 4, 5].freeze

      def prepare_weekday_heatmap
        cells = @report[:weekday_hour_distribution]
        start = BusinessDay.start_hour.to_i
        ordered = (0..23).map { |i| (start + i) % 24 }
        busy = ordered.each_index.select { |i| cells.keys.any? { |(_, h)| h == ordered[i] } }
        hours = busy.empty? ? [] : ordered[busy.first..busy.last]
        days = (@start_date..@end_date).group_by(&:wday).transform_values(&:size)

        rows = WEEKDAYS_SAT_FIRST.map do |wday|
          n = days.fetch(wday, 0)
          values = hours.map do |hour|
            c = cells.fetch([wday, hour], { count: 0, sales_cents: 0 })
            { hour: hour, count: c[:count], sales_cents: c[:sales_cents],
              avg_count: n.positive? ? c[:count].to_f / n : 0.0,
              avg_sales_cents: n.positive? ? c[:sales_cents].to_f / n : 0.0 }
          end
          { wday: wday, days: n, cells: values,
            avg_count: values.sum { |v| v[:avg_count] }, avg_sales_cents: values.sum { |v| v[:avg_sales_cents] } }
        end

        all = rows.flat_map { |r| r[:cells] }
        @heatmap = {
          hours: hours, rows: rows,
          max_count: all.map { |v| v[:avg_count] }.max.to_f,
          max_sales_cents: all.map { |v| v[:avg_sales_cents] }.max.to_f
        }
      end

      # The PDF and CSV follow the page: same view, category filter and sort,
      # but always every item (the page's "top 10" preview is a screen
      # convenience). modifiers=0 leaves out the modifier choices.
      def sales_pdf
        ::Accounting::PdfReportService.new(**export_args)
      end

      def export_args
        {
          report: @report, start_date: @start_date, end_date: @end_date,
          previous: @previous, previous_start: @previous_start, previous_end: @previous_end,
          orders_by_hour: @orders_by_hour, item_view: @item_view, items: @items,
          category_groups: @category_groups, item_category: @item_category,
          location: @location, include_open: @include_open, company: Current.company,
          modifiers: params[:modifiers] != "0"
        }
      end
    end
  end
end
