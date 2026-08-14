# frozen_string_literal: true

require "csv"

module Admin
  module Inventory
    class IngredientsController < BaseController
      before_action :set_ingredient, only: %i[show edit update destroy adjust adjustments]

      SORT_COLUMNS = %w[code name quantity_on_hand suppliers status cost_per_unit_cents stock_value].freeze

      def index
        authorize_inventory_index!

        @stock_filter = params[:stock].presence
        @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
        @sort = SORT_COLUMNS.include?(params[:sort].to_s) ? params[:sort].to_s : "name"
        @direction = params[:dir].to_s == "desc" ? "desc" : "asc"
        @q = Ingredient.ransack(params[:q])
        scope = @q.result.includes(:ingredient_category, :suppliers, :unit_ref)
        scope = scope.active if @status == "active"
        scope = scope.where(active: false) if @status == "inactive"
        @ingredients = apply_sort(apply_stock_filter(scope))

        respond_to do |format|
          format.html do
            @filtered = @stock_filter.present? || params[:q].present? || @status != "active"
            @low_stock_count = Ingredient.active.low_stock.count
            @out_of_stock_count = Ingredient.active.out_of_stock.count
            @expiring_count = Ingredient.active.expiring_soon.count
            @total_ingredients = Ingredient.active.count
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
        @stock_batches = @ingredient.stock_batches.fifo_order.includes(:supplier)
        @adjustments = @ingredient.stock_adjustments.includes(:user, :unit_ref, :location).order(created_at: :desc).limit(50)
        @recipes = @ingredient.recipes.includes(:menu_item, :unit_ref)
        @supplier_links = @ingredient.supplier_ingredients.includes(:supplier)
        @ingredient_units = @ingredient.ingredient_units.includes(:unit_ref)
        load_branch_stock
        @audits = @ingredient.audits.includes(:user).reorder(version: :desc)
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
          .includes(:user, :unit_ref, :location)
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

      private

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
          reorder_threshold: ingredient.reorder_threshold
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

      def ingredient_params
        permitted = params.require(:ingredient).permit(
          :name, :code, :ingredient_category_id, :unit_id, :reorder_threshold,
          :quantity_on_hand, :cost_per_unit_dollars, :active, :shelf_life_days,
          ingredient_units_attributes: %i[id unit_id base_units_per_unit _destroy]
        )
        dollars = permitted.delete(:cost_per_unit_dollars)
        permitted[:cost_per_unit_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        permitted[:shelf_life_days] = nil if permitted[:shelf_life_days].blank?
        permitted
      end
    end
  end
end
