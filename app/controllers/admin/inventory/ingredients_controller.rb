# frozen_string_literal: true

require "csv"

module Admin
  module Inventory
    class IngredientsController < BaseController
      before_action :set_ingredient,
        only: %i[show edit update destroy adjust adjustments batches sync_cost_from_last_invoice]

      SORT_COLUMNS = %w[code name quantity_on_hand suppliers status cost_per_unit_cents stock_value].freeze

      def index
        authorize_inventory_index!

        @stock_filter = params[:stock].presence
        @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
        @supplier_id = resolve_supplier_filter(params[:supplier_id])
        @sort = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : "name"
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
        @q = Ingredient.ransack(params[:q])
        scope = @q.result.includes(:ingredient_category, :suppliers, :unit_ref)
        scope = scope.active if @status == "active"
        scope = scope.where(active: false) if @status == "inactive"
        scope = apply_supplier_filter(scope)
        @ingredients = apply_sort(apply_stock_filter(scope))

        respond_to do |format|
          format.html do
            @suppliers = Supplier.active.order(:name)
            @filtered = @stock_filter.present? || params[:q].present? || @status != "active" || @supplier_id.present?
            @low_stock_count = Ingredient.active.low_stock.count
            @out_of_stock_count = Ingredient.active.out_of_stock.count
            @expiring_count = Ingredient.active.expiring_soon.count
            @total_ingredients = Ingredient.active.count
            @accessible_locations = Location.active.ordered
              .where(id: current_user.accessible_location_ids)
          end
          format.csv do
            send_data stock_by_location_csv(@ingredients),
              filename: "ingredient-stock-by-location-#{Date.current}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      def show
        authorize_inventory!(:show)
        @stock_batches = @ingredient.stock_batches.fifo_order.includes(:supplier).limit(20)
        @stock_batches_total = @ingredient.stock_batches.count
        @adjustments = @ingredient.stock_adjustments
          .includes(:user, :unit_ref, :location, :stock_transfer, stock_batch: { vendor_invoice_line: :vendor_invoice })
          .order(created_at: :desc).limit(25)
        @recipes = @ingredient.recipes.includes(:menu_item, :unit_ref)
        @supplier_links = @ingredient.supplier_ingredients.includes(:supplier)
        @ingredient_units = @ingredient.ingredient_units.includes(:unit_ref)
        load_branch_stock
        load_balance_history_chart
        @last_invoice_cost = ::Inventory::IngredientLastInvoiceCost.new(@ingredient).call
        @audits = @ingredient.audits.includes(:user).reorder(version: :desc).limit(50)
        @audits_total = @ingredient.audits.count
      end

      # Full, paginated adjustment ledger for one ingredient, filterable by
      # location and date range (the recent-adjustments panel on #show is capped
      # at 50 — this is the "view all" drill-down).
      def adjustments
        authorize_inventory!(:show)

        @location_id = params[:location_id].presence
        @start_date = params[:start_date].presence&.to_date
        @end_date = params[:end_date].presence&.to_date

        scope = @ingredient.stock_adjustments
          .includes(:user, :unit_ref, :location, :stock_transfer, stock_batch: { vendor_invoice_line: :vendor_invoice })
          .order(created_at: :desc)
        scope = scope.where(location_id: @location_id) if @location_id
        scope = scope.where(stock_adjustments: { created_at: @start_date.beginning_of_day.. }) if @start_date
        scope = scope.where(stock_adjustments: { created_at: ..@end_date.end_of_day }) if @end_date

        respond_to do |format|
          format.html do
            @pagy, @adjustments = pagy(:offset, scope, limit: 50)
            @locations = Location.active.central_kitchens.ordered.to_a +
                         Location.active.branches.ordered.to_a
          end
          format.csv do
            name = @ingredient.code.to_s.parameterize.presence || "ingredient"
            send_data adjustments_csv(scope),
              filename: "adjustments-#{name}-#{Date.current}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      rescue Date::Error, ArgumentError
        redirect_to admin_inventory_ingredient_path(@ingredient),
          alert: t("inventory.ingredients.adjustments.invalid_dates")
      end

      def batches
        authorize_inventory!(:show)

        @location_id  = params[:location_id].presence
        @show_empty   = params[:show_empty] == "1"
        @supplier_id  = params[:supplier_id].presence

        scope = @ingredient.stock_batches
          .includes(:supplier, :location)
          .fifo_order
        scope = scope.where(location_id: @location_id) if @location_id
        scope = scope.where(supplier_id: @supplier_id) if @supplier_id
        scope = scope.with_stock unless @show_empty

        respond_to do |format|
          format.html do
            @pagy, @batches = pagy(:offset, scope, limit: 50)
            @locations  = Location.active.central_kitchens.ordered.to_a +
                          Location.active.branches.ordered.to_a
            @suppliers  = Supplier.active.order(:name)
          end
          format.csv do
            name = @ingredient.code.to_s.parameterize.presence || "ingredient"
            send_data batches_csv(scope),
              filename: "batches-#{name}-#{Date.current}.csv",
              type: "text/csv; charset=utf-8"
          end
        end
      end

      def new
        @ingredient = Ingredient.new
        authorize_inventory!(:create)
        load_form_data
      end

      def create
        @ingredient = Ingredient.new(ingredient_params)
        authorize_inventory!(:create)
        load_form_data

        if stock_location_required? && stock_location.blank?
          @ingredient.errors.add(:base, t("inventory.ingredients.form.stock_location_required"))
          return render :new, status: :unprocessable_entity
        end

        ActiveRecord::Base.transaction do
          @ingredient.save!
          assign_initial_stock_location!(@ingredient, stock_location) if stock_location
        end

        redirect_to admin_inventory_ingredient_path(@ingredient), notice: t("flash.ingredient.created")
      rescue ActiveRecord::RecordInvalid
        render :new, status: :unprocessable_entity
      end

      def edit
        authorize_inventory!(:update)
        load_form_data
        load_supplier_links_data
      end

      def update
        authorize_inventory!(:update)
        if @ingredient.update(ingredient_params)
          redirect_to admin_inventory_ingredient_path(@ingredient), notice: t("flash.ingredient.updated")
        else
          load_form_data
          load_supplier_links_data
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:destroy)
        @ingredient.destroy
        redirect_to admin_inventory_ingredients_path, notice: t("flash.ingredient.removed")
      end

      def adjust
        authorize_inventory!(:adjust)
        # A location is mandatory: stock lives at a location, and it's what lets
        # the adjustment maintain that location's FIFO batch ledger.
        location = Location.find_by(id: params[:location_id])
        if location.blank?
          redirect_to admin_inventory_ingredient_path(@ingredient),
            alert: t("inventory.ingredients.show.location_required")
          return
        end

        # The delta may be entered in an alternate unit; store it in the base unit
        # and keep the entered unit for display.
        delta = @ingredient.to_base(BigDecimal(params[:quantity_delta].to_s), params[:unit])
        StockAdjustment.create!(
          ingredient: @ingredient,
          user: current_user,
          location: location,
          quantity_delta: delta,
          unit: params[:unit].presence,
          adjustment_type: params[:adjustment_type],
          reason_notes: params[:reason_notes],
          maintain_batches: true
        )
        ::Inventory::CheckLowStockJob.perform_later(@ingredient.id) if @ingredient.reload.low_stock?
        redirect_to admin_inventory_ingredient_path(@ingredient), notice: t("flash.ingredient.adjusted")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_inventory_ingredient_path(@ingredient), alert: e.record.errors.full_messages.to_sentence
      end

      def low_stock
        authorize_inventory_index!
        @ingredients = Ingredient.active.low_stock.includes(:ingredient_category).order(:name)
        render :low_stock
      end

      # Adopts the most recent invoiced unit cost as the master cost. Nothing
      # updates that column automatically, so this is the manual catch-up — always
      # confirmed first, with the before/after spelled out in the view.
      def sync_cost_from_last_invoice
        authorize_inventory!(:update)
        result = ::Inventory::IngredientLastInvoiceCost.new(@ingredient).call
        return_to = safe_return_to || admin_inventory_ingredient_path(@ingredient)

        if result.nil?
          redirect_to return_to, alert: t("inventory.ingredients.cost_sync.unavailable")
          return
        end

        previous_cents = @ingredient.cost_per_unit_cents.to_i
        if previous_cents == result.unit_cost_cents.to_i
          redirect_to return_to, notice: t("inventory.ingredients.cost_sync.unchanged")
          return
        end

        @ingredient.update!(cost_per_unit_cents: result.unit_cost_cents)
        redirect_to return_to,
          notice: t("inventory.ingredients.cost_sync.applied",
            from: helpers.format_money(previous_cents),
            to: helpers.format_money(result.unit_cost_cents),
            invoice: result.invoice.invoice_number)
      end

      private

      # Allow a caller to pass ?return_to= so we redirect back to their page
      # (e.g. the valuation report) rather than the ingredient show page.
      # Only same-host paths are accepted to prevent open redirects.
      def safe_return_to
        url = params[:return_to].presence
        return nil if url.blank?

        uri = URI.parse(url)
        # Reject absolute URLs pointing at a different host; allow plain paths.
        return nil if uri.host.present? && uri.host != request.host

        url
      rescue URI::InvalidURIError
        nil
      end

      def set_ingredient
        @ingredient = Ingredient.find(params[:id])
      end

      def load_form_data
        @categories = IngredientCategory.active.ordered
        load_stock_locations if @ingredient&.new_record?
      end

      def load_stock_locations
        central_kitchens = Location.active.central_kitchens.ordered.to_a
        branches = Location.active.branches.ordered.to_a
        @stock_locations = central_kitchens + branches
        @default_stock_location = central_kitchens.first || @stock_locations.first
        @selected_stock_location_id = params[:stock_location_id].presence || @default_stock_location&.id
      end

      def stock_location
        return @stock_location if defined?(@stock_location)

        @stock_location = Location.active.find_by(id: params[:stock_location_id])
      end

      def stock_location_required?
        @stock_locations&.any?
      end

      def assign_initial_stock_location!(ingredient, location)
        ingredient.ingredient_locations.create!(
          location: location,
          quantity_on_hand: ingredient.quantity_on_hand,
          reorder_threshold: ingredient.reorder_threshold,
          max_quantity: ingredient.max_quantity
        )
      end

      def apply_stock_filter(scope)
        case @stock_filter
        when "low" then scope.low_stock
        when "out" then scope.out_of_stock
        when "expiring" then scope.expiring_soon.includes(:stock_batches)
        else scope
        end
      end

      # Blank = all; "none" = no supplier_ingredients; otherwise a specific active supplier.
      def resolve_supplier_filter(raw)
        value = raw.to_s.presence
        return if value.blank?
        return "none" if value == "none"

        Supplier.active.find_by(id: value)&.id
      end

      def apply_supplier_filter(scope)
        case @supplier_id
        when "none"
          scope.where.missing(:supplier_ingredients)
        when nil
          scope
        else
          scope.where(id: SupplierIngredient.where(supplier_id: @supplier_id).select(:ingredient_id))
        end
      end

      def apply_sort(scope)
        dir_sql = @direction == "desc" ? "DESC" : "ASC"
        case @sort
        when "code"
          scope.order(Arel.sql("LOWER(ingredients.code) #{dir_sql}"))
        when "quantity_on_hand"
          scope.order(quantity_on_hand: @direction.to_sym)
        when "cost_per_unit_cents"
          scope.order(cost_per_unit_cents: @direction.to_sym)
        when "stock_value"
          scope.order(Arel.sql("(ingredients.quantity_on_hand * ingredients.cost_per_unit_cents) #{dir_sql}"))
        when "suppliers"
          scope.order(Arel.sql(<<~SQL.squish))
            (SELECT COUNT(*) FROM supplier_ingredients
             WHERE supplier_ingredients.ingredient_id = ingredients.id) #{dir_sql},
            LOWER(ingredients.name) ASC
          SQL
        when "status"
          scope.order(Arel.sql(<<~SQL.squish))
            CASE
              WHEN ingredients.quantity_on_hand <= 0 THEN 0
              WHEN ingredients.quantity_on_hand <= ingredients.reorder_threshold THEN 1
              WHEN ingredients.quantity_on_hand <= ingredients.reorder_threshold * 1.2 THEN 2
              ELSE 3
            END #{dir_sql},
            LOWER(ingredients.name) ASC
          SQL
        else
          scope.order(Arel.sql("LOWER(ingredients.name) #{dir_sql}"))
        end
      end

      # One row per ingredient, one quantity column per active location, plus the
      # canonical company-wide total. A leading BOM keeps Excel happy with UTF-8
      # (Arabic names, currency) — same approach as the vendor-invoice export.
      def stock_by_location_csv(ingredients)
        ingredients = ingredients.to_a
        locations = Location.active.central_kitchens.ordered.to_a +
                    Location.active.branches.ordered.to_a
        quantities = IngredientLocation
          .where(ingredient_id: ingredients.map(&:id))
          .each_with_object({}) do |il, memo|
            memo[[il.ingredient_id, il.location_id]] = il.quantity_on_hand
          end
        status_labels = { out: "Out of stock", low: "Low", near: "Near low", ok: "OK" }

        body = CSV.generate do |csv|
          csv << ["Code", "Name", "Category", "Unit", *locations.map(&:name),
                  "Total on-hand", "Reorder threshold", "Status"]
          ingredients.each do |ing|
            csv << [
              ing.code,
              ing.name,
              ing.ingredient_category&.name,
              ing.unit,
              *locations.map { |loc| quantities[[ing.id, loc.id]] || 0 },
              ing.quantity_on_hand,
              ing.reorder_threshold,
              status_labels[ing.stock_status]
            ]
          end
        end
        "﻿#{body}"
      end

      # Full filtered adjustment ledger as CSV (honours the location/date filters,
      # ignores pagination). Quantities are the signed base-unit delta so rows for
      # one ingredient are directly summable. BOM keeps Excel UTF-8-happy.
      def adjustments_csv(scope)
        base_unit = @ingredient.unit
        body = CSV.generate do |csv|
          csv << ["Time", "Location", "Type", "Quantity", "Unit", "User", "Reason"]
          scope.each do |adj|
            csv << [
              adj.created_at.strftime("%Y-%m-%d %H:%M"),
              adj.location&.name,
              helpers.inventory_adjustment_type_label(adj.adjustment_type),
              adj.quantity_delta,
              base_unit,
              adj.user&.name,
              adj.reason_notes
            ]
          end
        end
        "﻿#{body}"
      end

      def batches_csv(scope)
        body = CSV.generate do |csv|
          csv << ["Received on", "Location", "Supplier", "Remaining", "Unit", "Expires on", "Expired?"]
          scope.each do |batch|
            csv << [
              batch.received_on&.strftime("%Y-%m-%d"),
              batch.location&.name,
              batch.supplier&.name,
              batch.quantity_remaining,
              @ingredient.unit,
              batch.expires_on&.strftime("%Y-%m-%d"),
              batch.expired? ? "Yes" : "No"
            ]
          end
        end
        "﻿#{body}"
      end

      def load_supplier_links_data
        @supplier_links = @ingredient.supplier_ingredients.includes(:supplier).order("suppliers.name")
        @available_suppliers = Supplier.active.where.not(id: @ingredient.supplier_ids).order(:name)
      end

      def load_branch_stock
        central_kitchens = Location.active.central_kitchens.ordered.to_a
        branches = Location.active.branches.ordered.to_a
        @stock_locations = central_kitchens + branches
        @ingredient_locations_by_location_id = @ingredient.ingredient_locations
          .where(location_id: @stock_locations.map(&:id))
          .index_by(&:location_id)
      end

      def load_balance_history_chart
        @chart_days = ::Inventory::IngredientBalanceHistoryService::ALLOWED_DAYS.include?(params[:chart_days].to_i) ?
          params[:chart_days].to_i :
          ::Inventory::IngredientBalanceHistoryService::DEFAULT_DAYS
        # Blank means every location — the ingredient's own total, which is the
        # only figure that includes movements recorded without a location.
        @chart_location = @stock_locations.find { |loc| loc.id == params[:chart_location_id] }
        @balance_history = ::Inventory::IngredientBalanceHistoryService.new(
          ingredient: @ingredient,
          days: @chart_days,
          location: @chart_location
        ).call
        # Second series on the same chart: what this stock cost over the window.
        # Purchase price does not vary by branch, so it stays company-wide and is
        # unaffected by the location filter.
        @price_history = ::Inventory::IngredientPriceHistoryService.new(
          ingredient: @ingredient,
          days: @chart_days
        ).call
      end

      def ingredient_params
        permitted = params.require(:ingredient).permit(
          :name, :code, :ingredient_category_id, :unit_id, :reorder_threshold, :max_quantity,
          :quantity_on_hand, :cost_per_unit_dollars, :selling_price_pounds, :active, :shelf_life_days,
          ingredient_units_attributes: %i[id unit_id base_units_per_unit purchase_unit _destroy]
        )
        # Only touch the cost when the request actually carried the field. Coercing
        # an absent key to 0 would silently wipe a maintained cost — and that value
        # drives the valuation report, menu recipe costing, and the price stamped on
        # manually added stock batches. A field that is present but blank still
        # means zero, so clearing it in the form keeps working.
        if permitted.key?(:cost_per_unit_dollars)
          dollars = permitted.delete(:cost_per_unit_dollars)
          permitted[:cost_per_unit_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        end

        permitted[:shelf_life_days] = nil if permitted[:shelf_life_days].blank?
        permitted
      end
    end
  end
end
