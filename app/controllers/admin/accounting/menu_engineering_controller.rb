# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    # Menu engineering matrix (see ::Accounting::MenuEngineeringService). One row
    # per menu item sold in the range, so no pagination: a menu has tens of items,
    # not thousands, and the classification needs them all anyway. Sortable by
    # every number, filtered by date range, branch, category and class, and
    # exportable as CSV.
    class MenuEngineeringController < BaseController
      before_action { require_feature!(:menu) }

      def index
        parse_date_range(default_start: 29.days.ago.to_date)
        @locations = Location.branches.ordered
        @location = @locations.find_by(id: params[:location_id]) if params[:location_id].present?
        @categories = Category.order(:position, :name)
        @category = @categories.find_by(id: params[:category_id]) if params[:category_id].present?
        klasses = ::Accounting::MenuEngineeringService::CLASSES + [::Accounting::MenuEngineeringService::NO_COST]
        @klass = params[:class] if klasses.include?(params[:class])
        @sort = ::Accounting::MenuEngineeringService::SORTS.include?(params[:sort]) ? params[:sort] : "total_margin"
        @direction = params[:dir] == "asc" ? "asc" : "desc"

        @result = ::Accounting::MenuEngineeringService
          .new(@start_date, @end_date, location_id: @location&.id, category_id: @category&.id)
          .call(sort: @sort, direction: @direction, klass: @klass)

        respond_to do |format|
          format.html
          format.csv { send_data rows_csv, filename: "menu-engineering-#{@start_date}-#{@end_date}.csv" }
        end
      end

      private

      def rows_csv
        scope = "accounting.menu_engineering"
        money = ->(cents) { format("%.2f", cents / 100.0) }
        CSV.generate(headers: true) do |csv|
          csv << %w[item category class units mix avg_price unit_cost unit_margin total_margin food_cost_pct]
            .map { |k| t("#{scope}.columns.#{k}") }
          @result.rows.each do |r|
            csv << [r.name, r.category_name, t("#{scope}.classes.#{r.klass}.name"), r.units,
                    r.mix_pct&.round(1), money.call(r.avg_price_cents), money.call(r.unit_cost_cents),
                    money.call(r.unit_margin_cents), money.call(r.margin_cents), r.food_cost_pct]
          end
        end
      end
    end
  end
end
