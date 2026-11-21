# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Delivery orders by delivery area (see ::Accounting::DeliveryAreaReportService).
    # One row per area, so no pagination: a branch has tens of areas, not
    # thousands. Sortable by every column; filtered by date range, branch and the
    # Sales report's include-open switch; exportable as CSV.
    class DeliveryAreaReportsController < BaseController
      before_action { require_feature!(:menu) }

      def index
        parse_date_range(default_start: Date.current.beginning_of_week(:saturday))
        @include_open = params[:include_open] == "1"
        @locations = Location.branches.ordered
        @location = @locations.find_by(id: params[:location_id]) if params[:location_id].present?
        @sort = ::Accounting::DeliveryAreaReportService::SORTS.include?(params[:sort]) ? params[:sort] : "orders"
        @direction = params[:dir] == "asc" ? "asc" : "desc"

        service = ::Accounting::DeliveryAreaReportService.new(@start_date, @end_date, location_id: @location&.id,
                                                                                    include_open: @include_open)
        @rows, @totals = service.rows(sort: @sort, direction: @direction)
        @chart_metric = ::Accounting::DeliveryAreaReportService::CHART_METRICS.include?(params[:chart]) ? params[:chart] : "orders"
        @chart_bars = service.chart_bars(@rows, metric: @chart_metric)

        respond_to do |format|
          format.html
          format.csv { send_data rows_csv, filename: "delivery-areas-#{@start_date}-#{@end_date}.csv" }
        end
      end

      private

      def rows_csv
        scope = "accounting.delivery_area_reports"
        CSV.generate(headers: true) do |csv|
          csv << [t("#{scope}.area"), t("accounting.sales_reports.branch"), t("#{scope}.orders"), t("#{scope}.share"),
                  t("#{scope}.fees"), t("#{scope}.avg_fee"), t("#{scope}.food"), t("#{scope}.avg_food")]
          @rows.each do |r|
            share = @totals.orders.zero? ? 0 : (100.0 * r.orders / @totals.orders).round(1)
            csv << [r.area ? r.area.display_name : t("#{scope}.no_area"), r.location&.name, r.orders, share,
                    format("%.2f", r.fee_cents / 100.0), format("%.2f", r.avg_fee_cents / 100.0),
                    format("%.2f", r.food_cents / 100.0), format("%.2f", r.avg_food_cents / 100.0)]
          end
        end
      end
    end
  end
end
