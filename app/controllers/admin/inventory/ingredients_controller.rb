# frozen_string_literal: true

module Admin
  module Inventory
    class IngredientsController < BaseController
      before_action :set_ingredient, only: %i[show edit update destroy adjust]

      def index
        authorize_inventory_index!

        @stock_filter = params[:stock].presence
        @status = %w[active inactive all].include?(params[:status]) ? params[:status] : "active"
        @q = Ingredient.ransack(params[:q])
        scope = @q.result.includes(:ingredient_category, :suppliers, :unit_ref)
        scope = scope.active if @status == "active"
        scope = scope.where(active: false) if @status == "inactive"
        @ingredients = apply_stock_filter(scope).order(:name)
        @filtered = @stock_filter.present? || params[:q].present? || @status != "active"
        @low_stock_count = Ingredient.active.low_stock.count
        @out_of_stock_count = Ingredient.active.out_of_stock.count
        @expiring_count = Ingredient.active.expiring_soon.count
        @total_ingredients = Ingredient.active.count
      end

      def show
        authorize_inventory!(:show)
        @stock_batches = @ingredient.stock_batches.fifo_order.includes(:supplier)
        @adjustments = @ingredient.stock_adjustments.includes(:user, :unit_ref).order(created_at: :desc).limit(50)
        @recipes = @ingredient.recipes.includes(:menu_item, :unit_ref)
        @supplier_links = @ingredient.supplier_ingredients.includes(:supplier)
        load_branch_stock
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
          :name, :ingredient_category_id, :unit_id, :reorder_threshold,
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
