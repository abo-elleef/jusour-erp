# frozen_string_literal: true

module Admin
  module Inventory
    class ReportsController < BaseController
      include ValuedReports

      # Buckets used by the vendor grouping for ingredients that don't resolve to a
      # single supplier. Symbols so they can't collide with a Supplier record.
      VENDOR_GROUP_NONE = :no_vendor
      VENDOR_GROUP_MULTIPLE = :multiple_vendors

      MOVEMENT_INCLUDES = [
        :user, :unit_ref, :location, :stock_transfer,
        { ingredient: :unit_ref, stock_batch: { vendor_invoice_line: :vendor_invoice } }
      ].freeze

      # Instantiating every row of an unfiltered month at once would be a large
      # object graph, so the movements CSV walks the ordered scope in slices.
      CSV_BATCH_SIZE = 2_000

      # Every stock movement in the company, across all items — the cross-item
      # counterpart to the per-ingredient ledger on the ingredient page.
      # Quantities are never totalled across items: they are each in their own
      # base unit, so only the per-item rollup adds anything up.
      def movements
        authorize_inventory_index!
        parse_date_range(default_start: Date.current.beginning_of_month)

        @ingredient = Ingredient.find_by(id: params[:ingredient_id])
        @location = Location.find_by(id: params[:location_id])
        @adjustment_type = params[:adjustment_type].presence_in(StockAdjustment::ADJUSTMENT_TYPES)
        @user = User.find_by(id: params[:user_id])
        @group_by_ingredient = params[:group] == "ingredient"

        scope = movements_scope
        @type_counts = scope.group(:adjustment_type).count
        @movement_count = @type_counts.values.sum
        @item_count = scope.distinct.count("stock_adjustments.ingredient_id")
        @addition_count = scope.additions.count
        @removal_count = @movement_count - @addition_count

        respond_to do |format|
          format.html do
            if @group_by_ingredient
              @item_rows = movements_by_ingredient(scope)
            else
              listing = scope.includes(*MOVEMENT_INCLUDES).order(created_at: :desc, id: :desc)
              @pagy, @movements = pagy(:offset, listing, limit: 50, count: @movement_count)
            end
            load_movement_filter_options
          end
          format.csv do
            send_data movements_csv(scope),
              filename: "stock-movements-#{@start_date}-#{@end_date}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      rescue Date::Error, ArgumentError
        redirect_to admin_inventory_reports_movements_path,
          alert: t("inventory.reports.movements.invalid_dates")
      end

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

      # The three figures accountants actually ask for about vendor spend, side by
      # side instead of folded into one invoice-total column (where credit notes
      # and actual cash paid are both invisible — see the Suppliers list):
      #   - goods bought:   gross VendorInvoice totals, any payment status
      #   - credit notes:   confirmed VendorCreditNote totals given back
      #   - actually paid:  cash that left via a payment voucher (AP ledger "ap_payment" leg)
      # Net purchases (goods bought minus credit notes) is derived, not stored.
      def vendor_purchases_summary
        authorize_inventory_index!
        parse_date_range(default_start: Date.current.beginning_of_month)

        @supplier = Supplier.find_by(id: params[:supplier_id])
        @suppliers = Supplier.active.order(:name)
        supplier_ids = @supplier ? [@supplier.id] : Supplier.pluck(:id)

        # Voiding leaves payment_status: "void" but never flips draft back to
        # true, so .posted alone still counts it — excluded here to match the
        # P&L (voiding deletes the invoice's journal entry outright).
        @purchases_cents_by_supplier = VendorInvoice.posted
          .where.not(payment_status: "void")
          .where(supplier_id: supplier_ids, invoice_date: @start_date..@end_date)
          .group(:supplier_id).sum(:total_cents)

        @credit_notes_cents_by_supplier = VendorCreditNote.confirmed
          .where(supplier_id: supplier_ids, credit_note_date: @start_date..@end_date)
          .group(:supplier_id).sum(:total_cents)

        # ap_payment legs are always negative (cash leaving); supplier_ap is the
        # system-managed ledger treasury type, one per supplier — see Treasury#supplier_ap.
        paid_by_supplier = TreasuryTransaction.where(kind: "ap_payment")
          .joins(:treasury).merge(Treasury.supplier_ap)
          .where(treasuries: { supplier_id: supplier_ids })
          .where(occurred_on: @start_date..@end_date)
          .group("treasuries.supplier_id").sum(:amount_cents)
        @paid_cents_by_supplier = paid_by_supplier.transform_values { |cents| -cents }

        active_ids = (@purchases_cents_by_supplier.keys +
                      @credit_notes_cents_by_supplier.keys +
                      @paid_cents_by_supplier.keys).uniq
        @rows = Supplier.where(id: active_ids).order(:name)

        @total_purchases_cents = @purchases_cents_by_supplier.values.sum
        @total_credit_notes_cents = @credit_notes_cents_by_supplier.values.sum
        @total_paid_cents = @paid_cents_by_supplier.values.sum
        @total_net_purchases_cents = @total_purchases_cents - @total_credit_notes_cents

        respond_to do |format|
          format.html
          format.csv do
            send_data vendor_purchases_summary_csv,
              filename: "vendor-purchases-summary-#{@start_date}-#{@end_date}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      private

      def movements_scope
        scope = StockAdjustment.for_current_company
          .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
        scope = scope.where(ingredient_id: @ingredient.id) if @ingredient
        scope = scope.where(location_id: @location.id) if @location
        scope = scope.where(adjustment_type: @adjustment_type) if @adjustment_type
        scope = scope.where(user_id: @user.id) if @user
        scope
      end

      def load_movement_filter_options
        @locations = Location.active.central_kitchens.ordered.to_a +
                     Location.active.branches.ordered.to_a
        @ingredients = Ingredient.order(:name)
        @users = User.active.order(:name)
        @filtered = @ingredient || @location || @adjustment_type || @user
      end

      # Net movement per item over the range. quantity_delta is stored in the
      # ingredient's base unit, so these sums are meaningful within a row — and
      # only within a row.
      def movements_by_ingredient(scope)
        totals = scope.group("stock_adjustments.ingredient_id").pluck(
          Arel.sql("stock_adjustments.ingredient_id"),
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(quantity_delta)"),
          Arel.sql("SUM(CASE WHEN quantity_delta > 0 THEN quantity_delta ELSE 0 END)"),
          Arel.sql("SUM(CASE WHEN quantity_delta < 0 THEN quantity_delta ELSE 0 END)")
        )
        ingredients = Ingredient.where(id: totals.map(&:first)).includes(:unit_ref).index_by(&:id)
        totals.filter_map do |id, count, net, additions, removals|
          ingredient = ingredients[id]
          next unless ingredient

          { ingredient: ingredient, count: count, net: net.to_d,
            additions: additions.to_d, removals: removals.to_d }
        end.sort_by { |row| row[:ingredient].name.to_s.downcase }
      end

      def each_movement(scope)
        return enum_for(:each_movement, scope) unless block_given?

        ordered = scope.includes(*MOVEMENT_INCLUDES).order(created_at: :desc, id: :desc)
        offset = 0
        loop do
          batch = ordered.offset(offset).limit(CSV_BATCH_SIZE).to_a
          break if batch.empty?

          batch.each { |row| yield row }
          offset += CSV_BATCH_SIZE
        end
      end

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

      # Unit is spelled out per row because quantities across items are in
      # different units and must not be summed in a spreadsheet.
      def movements_csv(scope)
        rows = [["Time", "Item", "Code", "Location", "Type", "Quantity", "Unit",
                 "Balance after", "User", "Reason"]]
        each_movement(scope).each do |adj|
          rows << [
            adj.created_at.strftime("%Y-%m-%d %H:%M"),
            adj.ingredient&.name,
            adj.ingredient&.code,
            adj.location&.name,
            helpers.inventory_adjustment_type_label(adj.adjustment_type),
            adj.quantity_delta,
            adj.ingredient&.unit,
            adj.balance_after,
            adj.user&.name,
            adj.reason_notes
          ]
        end
        "\ufeff#{build_csv(rows)}"
      end

      def vendor_purchases_summary_csv
        money = ->(cents) { helpers.format_money(cents) }
        build_csv(
          [
            ["Vendor purchases summary", "#{@start_date} to #{@end_date}"],
            ["Vendor", "Goods bought", "Credit notes", "Net purchases", "Actually paid"],
            *@rows.map do |supplier|
              bought = @purchases_cents_by_supplier[supplier.id] || 0
              credits = @credit_notes_cents_by_supplier[supplier.id] || 0
              paid = @paid_cents_by_supplier[supplier.id] || 0
              [supplier.name, money.(bought), money.(credits), money.(bought - credits), money.(paid)]
            end,
            [],
            ["Total goods bought", money.(@total_purchases_cents)],
            ["Total credit notes", money.(@total_credit_notes_cents)],
            ["Total net purchases", money.(@total_net_purchases_cents)],
            ["Total actually paid", money.(@total_paid_cents)]
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
