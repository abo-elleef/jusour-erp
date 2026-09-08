# frozen_string_literal: true

module Admin
  module Inventory
    class ReportsController < BaseController
      # Buckets used by the vendor grouping for ingredients that don't resolve to a
      # single supplier. Symbols so they can't collide with a Supplier record.
      VENDOR_GROUP_NONE = :no_vendor
      VENDOR_GROUP_MULTIPLE = :multiple_vendors

      def valuation
        authorize_inventory_index!
        @group_by = params[:group_by].to_s == "vendor" ? "vendor" : "category"
        @ingredients = Ingredient.active
          .includes(:ingredient_category, supplier_ingredients: :supplier)
          .order(:name)
        # Categories follow their configured position, not the alphabet — this was
        # ordering by ingredient_categories.name, the only grouped view that did.
        # Ordering ingredients by name alone also drops the string order that
        # referenced the joined table.
        @by_category = @ingredients
          .group_by(&:ingredient_category)
          .sort_by { |category, _| IngredientCategory.grouping_sort_key(category) }
          .to_h
        @by_vendor = group_by_vendor(@ingredients)
        @total_cost_value = @ingredients.sum(&:stock_value_cents)
        @ingredient_count = @ingredients.size
        @category_count = @by_category.size
        @vendor_count = @by_vendor.keys.count { |key| key.is_a?(Supplier) }
        # Items whose unit cost can't produce a real value — they sit in the report
        # at 0.00 and are easy to miss without a count up front.
        @cost_issue_ingredients = @ingredients.select { |i| i.cost_per_unit_cents.to_i <= 0 }

        # Build a hash { ingredient => Result|nil } for the invoice cost column.
        # Uses the batch loader: 1 query for all ingredients instead of N.
        @last_invoice_costs = ::Inventory::IngredientLastInvoiceCost.batch_call(@ingredients)

        respond_to do |format|
          format.html
          format.csv { send_data valuation_csv, filename: "valuation-#{Date.current}.csv" }
        end
      end

      def variance
        authorize_inventory_index!
        parse_date_range

        result = ::Inventory::IngredientConsumptionService.new(@start_date, @end_date).call
        @completed_orders_count = result[:completed_orders_count]
        @variance_rows = result[:rows]
        @ingredient_count = @variance_rows.size
        @high_variance_count = @variance_rows.count { |row| row[:variance_pct].abs > 10 }

        respond_to do |format|
          format.html
          format.csv { send_data variance_csv, filename: "variance-#{@start_date}-#{@end_date}.csv" }
        end
      end

      # Goods actually moved between locations, from completed transfers only.
      def transfer_trends
        authorize_inventory_index!
        parse_date_range(default_start: 30.days.ago.to_date)

        @from_location = Location.find_by(id: params[:from_location_id])
        @to_location = Location.find_by(id: params[:to_location_id])
        @granularity = params[:granularity]
        @locations = Location.active.ordered

        @trends = ::Inventory::TransferTrendsService.new(
          start_date: @start_date,
          end_date: @end_date,
          from_location: @from_location,
          to_location: @to_location,
          granularity: @granularity
        ).call

        respond_to do |format|
          format.html
          format.csv do
            send_data transfer_trends_csv,
              filename: "transfer-trends-#{@start_date}-#{@end_date}.csv"
          end
        end
      end

      # What happened to purchase prices between this period and the one before,
      # and how much of the spend change was price rather than buying differently.
      def vendor_basket
        authorize_inventory_index!
        parse_date_range(default_start: Date.current.beginning_of_month)

        @supplier = Supplier.find_by(id: params[:supplier_id])
        @category = IngredientCategory.find_by(id: params[:category_id])
        @suppliers = Supplier.active.order(:name)
        @categories = IngredientCategory.ordered

        @basket = ::Inventory::VendorBasketDriftService.new(
          start_date: @start_date,
          end_date: @end_date,
          supplier: @supplier,
          category: @category
        ).call

        respond_to do |format|
          format.html
          format.csv do
            send_data vendor_basket_csv,
              filename: "purchase-price-drift-#{@start_date}-#{@end_date}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      # Every ingredient lands in exactly one bucket, so vendor subtotals still add
      # up to the same grand total as the category view. An ingredient can be
      # linked to several vendors, so the tie-break is: the preferred link, else the
      # only link, else a "multiple vendors" bucket — which doubles as a nudge to go
      # set a preferred vendor rather than silently picking one.
      def group_by_vendor(ingredients)
        groups = ingredients.group_by { |ingredient| vendor_group_for(ingredient) }
        named, unnamed = groups.partition { |key, _| key.is_a?(Supplier) }
        named.sort_by { |supplier, _| supplier.name.to_s.downcase }.to_h.merge(
          # Ambiguous first, then unsourced — both are things to act on, so they
          # sit at the end rather than being buried between vendors.
          unnamed.sort_by { |key, _| key == VENDOR_GROUP_MULTIPLE ? 0 : 1 }.to_h
        )
      end

      def vendor_group_for(ingredient)
        links = ingredient.supplier_ingredients
        return VENDOR_GROUP_NONE if links.empty?
        return links.first.supplier if links.size == 1

        preferred = links.select(&:preferred)
        preferred.size == 1 ? preferred.first.supplier : VENDOR_GROUP_MULTIPLE
      end

      def vendor_group_label(key)
        case key
        when VENDOR_GROUP_NONE then t("inventory.reports.valuation.no_vendor")
        when VENDOR_GROUP_MULTIPLE then t("inventory.reports.valuation.multiple_vendors")
        else key.name
        end
      end
      helper_method :vendor_group_label

      def valuation_csv
        build_csv(
          [
            %w[Category Vendor Ingredient Unit OnHand CostPerUnitCents StockValueCents],
            *@ingredients.map do |i|
              [i.ingredient_category.name, vendor_group_label(vendor_group_for(i)),
               i.name, i.unit, i.quantity_on_hand, i.cost_per_unit_cents, i.stock_value_cents]
            end,
            [],
            ["Total", "", "", "", "", "", @total_cost_value]
          ]
        )
      end

      def variance_csv
        build_csv(
          [
            %w[Ingredient Theoretical Actual Variance VariancePct],
            *@variance_rows.map do |row|
              [
                row[:ingredient].name,
                row[:theoretical],
                row[:actual],
                row[:variance],
                row[:variance_pct]
              ]
            end
          ]
        )
      end

      # One row per ingredient and route, with the unit spelled out — the numbers
      # are only comparable within a row.
      def transfer_trends_csv
        header = ["Ingredient", "Unit", "From", "To", "Transfers", "Total"] + @trends.period_labels
        build_csv(
          [
            header,
            *@trends.rows.map do |row|
              [
                row.ingredient.name,
                row.unit,
                row.from_location.name,
                row.to_location.name,
                row.transfer_count,
                row.total
              ] + @trends.periods.map { |period| row.quantities[period] }
            end
          ]
        )
      end

      def vendor_basket_csv
        money = ->(cents) { helpers.format_money(cents) }
        build_csv(
          [
            ["Purchase price drift", "#{@start_date} to #{@end_date} vs #{@basket.prior_start_date} to #{@basket.prior_end_date}"],
            ["Ingredient", "Unit", "Qty before", "Qty now", "Price before", "Price now",
             "Change %", "Price impact", "Spend before", "Spend now", "Verify"],
            *@basket.rows.map do |row|
              [
                row.ingredient.name, row.unit,
                row.prior_quantity, row.quantity,
                money.(row.prior_price_cents), money.(row.price_cents),
                row.price_change_pct, money.(row.price_impact_cents),
                money.(row.prior_spend_cents), money.(row.spend_cents),
                row.suspicious? ? "check invoice" : ""
              ]
            end,
            [],
            ["Spend before", money.(@basket.prior_spend_cents)],
            ["Spend now", money.(@basket.spend_cents)],
            ["Price effect", money.(@basket.price_effect_cents)],
            ["Buying-mix effect", money.(@basket.mix_effect_cents)]
          ]
        )
      end

      def build_csv(rows)
        rows.map { |row| row.map { |cell| escape_csv_cell(cell) }.join(",") }.join("\n")
      end

      def escape_csv_cell(value)
        str = value.nil? ? "" : value.to_s
        return str unless str.match?(/[",\n\r]/)

        "\"#{str.gsub('"', '""')}\""
      end
    end
  end
end
