# frozen_string_literal: true

module Admin
  module Inventory
    # The five valued inventory reports SAQR's accountant asked for (2026-10-30):
    # item movement card, valued adjustments, stock levels, stagnant items and
    # turnover. Each reads Inventory::Reports::*; every one has CSV and a print
    # view (?print=1 renders every row unpaginated and opens the print dialog).
    module ValuedReports
      extend ActiveSupport::Concern

      ITEM_CARD_PAGE_SIZE = 100

      included do
        helper_method :print_mode?
      end

      def item_card
        authorize_inventory_index!
        parse_date_range(default_start: Date.current.beginning_of_month)
        load_report_filters
        @ingredient = Ingredient.find_by(id: params[:ingredient_id])

        report = ::Inventory::Reports::ItemCardService.new(
          start_date: @start_date, end_date: @end_date,
          ingredient: @ingredient, location: @location, category: @category
        )
        if @ingredient
          @totals = report.totals
          movements = report.movements
          if print_mode? || request.format.csv?
            @movements = movements.to_a
          else
            @pagy, @movements = pagy(:offset, movements, limit: ITEM_CARD_PAGE_SIZE, count: @totals.count)
          end
        else
          @summaries = report.summaries
        end

        respond_to do |format|
          format.html { @ingredients = Ingredient.order(:name) }
          format.csv { send_report_csv(item_card_csv, "item-card") }
        end
      end

      def adjustments
        authorize_inventory_index!
        parse_date_range(default_start: Date.current.beginning_of_month)
        load_report_filters
        @types = ::Inventory::Reports::AdjustmentsService.normalize_types(params[:types])

        @result = ::Inventory::Reports::AdjustmentsService.new(
          start_date: @start_date, end_date: @end_date, types: @types,
          location: @location, category: @category
        ).call

        respond_to do |format|
          format.html
          format.csv { send_report_csv(adjustments_csv, "stock-adjustments") }
        end
      end

      def stock_levels
        authorize_inventory_index!
        load_report_filters
        @supplier = Supplier.find_by(id: params[:supplier_id])
        @suppliers = Supplier.active.order(:name)
        @cover_days = params[:cover_days].to_i.clamp(1, 90)
        @cover_days = ::Inventory::Reports::StockLevelsService::DEFAULT_COVER_DAYS if params[:cover_days].blank?
        @status = params[:status].presence_in(::Inventory::Reports::StockLevelsService::STATUSES + ["all"]) || "below_min"

        all_rows = ::Inventory::Reports::StockLevelsService.new(
          location: @location, supplier: @supplier, category: @category, cover_days: @cover_days
        ).call
        @status_counts = all_rows.group_by(&:status).transform_values(&:size)
        @rows = @status == "all" ? all_rows : all_rows.select { |row| row.status == @status }

        respond_to do |format|
          format.html
          format.csv { send_report_csv(stock_levels_csv, "stock-levels", dated: false) }
        end
      end

      def stagnant_items
        authorize_inventory_index!
        load_report_filters
        @days = params[:days].to_i.clamp(1, 365)
        @days = ::Inventory::Reports::StagnantItemsService::DEFAULT_DAYS if params[:days].blank?

        @rows = ::Inventory::Reports::StagnantItemsService.new(
          days: @days, location: @location, category: @category
        ).call

        respond_to do |format|
          format.html
          format.csv { send_report_csv(stagnant_items_csv, "stagnant-items", dated: false) }
        end
      end

      def turnover
        authorize_inventory_index!
        parse_date_range(default_start: Date.current.beginning_of_month)
        load_report_filters

        @result = ::Inventory::Reports::TurnoverService.new(
          start_date: @start_date, end_date: @end_date, location: @location, category: @category
        ).call

        respond_to do |format|
          format.html
          format.csv { send_report_csv(turnover_csv, "inventory-turnover") }
        end
      end

      private

      def print_mode?
        params[:print].present?
      end

      def load_report_filters
        @location = Location.find_by(id: params[:location_id])
        @category = IngredientCategory.find_by(id: params[:category_id])
        @locations = Location.active.central_kitchens.ordered.to_a + Location.active.branches.ordered.to_a
        @categories = IngredientCategory.ordered
      end

      def send_report_csv(body, name, dated: true)
        suffix = dated ? "#{@start_date}-#{@end_date}" : Date.current.to_s
        send_data "﻿#{body}", filename: "#{name}-#{suffix}.csv", type: "text/csv; charset=utf-8"
      end

      # Plain decimals, not formatted money: these files are opened in a
      # spreadsheet to be added up.
      def csv_amount(cents)
        cents.nil? ? "" : format("%.2f", cents.to_d / 100)
      end

      def csv_qty(quantity)
        quantity.nil? ? "" : quantity.to_d.round(3).to_s("F")
      end

      def report_scope_line
        [@location&.name || t("inventory.reports.shared.all_locations"), @category&.name].compact.join(" / ")
      end

      def item_card_csv
        if @ingredient
          t_ = @totals
          rows = [
            [t("inventory.reports.item_card.title"), @ingredient.name, @ingredient.unit, report_scope_line,
             "#{@start_date} - #{@end_date}"],
            ["Date", "Location", "Type", "Reference", "In", "Out", "Balance", "Unit cost", "In value",
             "Out value", "Estimated cost", "User"],
            ["", "", t("inventory.reports.item_card.opening"), "", "", "", csv_qty(t_.opening_qty), "", "", "", "", ""]
          ]
          @movements.each do |adj|
            value = (adj.quantity_delta.abs * adj.unit_cost_cents.to_i).round
            rows << [adj.created_at.strftime("%Y-%m-%d %H:%M"), adj.location&.name,
                     helpers.inventory_adjustment_type_label(adj.adjustment_type), adj.reason_notes,
                     adj.quantity_delta.positive? ? csv_qty(adj.quantity_delta) : "",
                     adj.quantity_delta.negative? ? csv_qty(-adj.quantity_delta) : "",
                     csv_qty(adj.running_qty), csv_amount(adj.unit_cost_cents),
                     adj.quantity_delta.positive? ? csv_amount(value) : "",
                     adj.quantity_delta.negative? ? csv_amount(value) : "",
                     adj.unit_cost_estimated ? "yes" : "", adj.user&.name]
          end
          rows << []
          rows << ["", "", t("inventory.reports.item_card.totals"), "", csv_qty(t_.qty_in), csv_qty(t_.qty_out),
                   csv_qty(t_.closing_qty), "", csv_amount(t_.value_in), csv_amount(t_.value_out), "", ""]
          rows << ["", "", t("inventory.reports.item_card.opening_value"), csv_amount(t_.opening_value)]
          rows << ["", "", t("inventory.reports.item_card.closing_value"), csv_amount(t_.closing_value)]
          build_csv(rows)
        else
          build_csv([
            [t("inventory.reports.item_card.title"), report_scope_line, "#{@start_date} - #{@end_date}"],
            ["Item", "Code", "Category", "Unit", "Opening qty", "Opening value", "In qty", "In value",
             "Out qty", "Out value", "Closing qty", "Closing value"],
            *@summaries.map do |row|
              [row.ingredient.name, row.ingredient.code, row.ingredient.ingredient_category&.name, row.ingredient.unit,
               csv_qty(row.opening_qty), csv_amount(row.opening_value), csv_qty(row.qty_in), csv_amount(row.value_in),
               csv_qty(row.qty_out), csv_amount(row.value_out), csv_qty(row.closing_qty), csv_amount(row.closing_value)]
            end,
            [],
            ["Total", "", "", "", "", csv_amount(@summaries.sum(&:opening_value)), "",
             csv_amount(@summaries.sum(&:value_in)), "", csv_amount(@summaries.sum(&:value_out)), "",
             csv_amount(@summaries.sum(&:closing_value))]
          ])
        end
      end

      def adjustments_csv
        section = lambda do |label, rows|
          [[label], ["Item", "Code", "Category", "Unit", "Quantity", "Value", "Movements", "Estimated cost rows"],
           *rows.map do |row|
             [row.ingredient.name, row.ingredient.code, row.ingredient.ingredient_category&.name, row.ingredient.unit,
              csv_qty(row.quantity), csv_amount(row.value_cents), row.count, row.estimated]
           end,
           ["Total", "", "", "", "", csv_amount(rows.sum(&:value_cents))], []]
        end
        build_csv(
          [[t("inventory.reports.adjustments.title"), report_scope_line, "#{@start_date} - #{@end_date}",
            @types.map { |type| helpers.inventory_adjustment_type_label(type) }.join(" + ")], []] +
          section.(t("inventory.reports.adjustments.surplus"), @result.surplus) +
          section.(t("inventory.reports.adjustments.deficit"), @result.deficit) +
          [[t("inventory.reports.adjustments.net"), csv_amount(@result.net_cents)]]
        )
      end

      def stock_levels_csv
        build_csv([
          [t("inventory.reports.stock_levels.title"), report_scope_line, @supplier&.name, Date.current.to_s],
          ["Item", "Code", "Supplier", "Unit", "On hand", "Min", "Max", "Avg daily usage", "Days of cover",
           "Status", "Target", "Target basis", "Order qty", "Order unit", "Order value"],
          *@rows.map do |row|
            [row.ingredient.name, row.ingredient.code, row.supplier&.name, row.ingredient.unit,
             csv_qty(row.on_hand), csv_qty(row.min), csv_qty(row.max), csv_qty(row.avg_daily_usage),
             row.days_of_cover, t("inventory.reports.stock_levels.statuses.#{row.status}"),
             csv_qty(row.target), row.target_basis && t("inventory.reports.stock_levels.basis.#{row.target_basis}"),
             row.order_quantity.positive? ? csv_qty(row.order_quantity) : "", row.order_unit,
             row.order_quantity.positive? ? csv_amount(row.order_cents) : ""]
          end,
          [],
          ["Total", "", "", "", "", "", "", "", "", "", "", "", "", "", csv_amount(@rows.sum(&:order_cents))]
        ])
      end

      def stagnant_items_csv
        build_csv([
          [t("inventory.reports.stagnant_items.title"), report_scope_line,
           t("inventory.reports.stagnant_items.days_value", days: @days), Date.current.to_s],
          ["Item", "Code", "Category", "Unit", "On hand", "Value", "Last used", "Days since used", "Last movement"],
          *@rows.map do |row|
            [row.ingredient.name, row.ingredient.code, row.ingredient.ingredient_category&.name, row.ingredient.unit,
             csv_qty(row.on_hand), csv_amount(row.value_cents), row.last_used_at&.to_date, row.days_since_used,
             row.last_moved_at&.to_date]
          end,
          [],
          ["Total", "", "", "", "", csv_amount(@rows.sum(&:value_cents))]
        ])
      end

      def turnover_csv
        result = @result
        build_csv([
          [t("inventory.reports.turnover.title"), report_scope_line, "#{@start_date} - #{@end_date}"],
          ["Item", "Code", "Category", "Unit", "Opening qty", "Closing qty", "Used qty", "Qty turnover",
           "Opening value", "Closing value", "Average value", "Used value", "Turnover", "Days of stock"],
          *result.rows.map do |row|
            [row.ingredient.name, row.ingredient.code, row.ingredient.ingredient_category&.name, row.ingredient.unit,
             csv_qty(row.opening_qty), csv_qty(row.closing_qty), csv_qty(row.used_qty), row.quantity_turnover,
             csv_amount(row.opening_value), csv_amount(row.closing_value), csv_amount(row.average_value.round),
             csv_amount(row.used_value), row.turnover, result.days_of_stock(row)]
          end,
          [],
          ["Total", "", "", "", "", "", "", "", "", "", csv_amount(result.average_value.round),
           csv_amount(result.used_value), result.turnover, result.days_of_stock]
        ])
      end
    end
  end
end
