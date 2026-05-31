# frozen_string_literal: true

module Admin
  module Inventory
    class IngredientsController < BaseController
      before_action :set_ingredient, only: %i[show edit update destroy adjust]

      def index
        authorize_inventory_index!

        @stock_filter = params[:stock].presence
        @q = Ingredient.ransack(params[:q])
        scope = @q.result.active.includes(:ingredient_category, :suppliers)
        @ingredients = apply_stock_filter(scope).order(:name)
        @filtered = @stock_filter.present? || params[:q].present?
        @low_stock_count = Ingredient.active.low_stock.count
        @out_of_stock_count = Ingredient.active.out_of_stock.count
        @expiring_count = Ingredient.active.expiring_soon.count
        @total_ingredients = Ingredient.active.count
      end

      def show
        authorize_inventory!(:show)
        @stock_batches = @ingredient.stock_batches.fifo_order.includes(:supplier)
        @adjustments = @ingredient.stock_adjustments.includes(:user).order(created_at: :desc).limit(50)
        @recipes = @ingredient.recipes.includes(:menu_item)
        @supplier_links = @ingredient.supplier_ingredients.includes(:supplier)
      end

      def new
        @ingredient = Ingredient.new
        authorize_inventory!(:create)
        load_form_data
      end

      def create
        @ingredient = Ingredient.new(ingredient_params)
        authorize_inventory!(:create)
        if @ingredient.save
          redirect_to admin_inventory_ingredient_path(@ingredient), notice: t("flash.ingredient.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
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
        delta = BigDecimal(params[:quantity_delta].to_s)
        StockAdjustment.create!(
          ingredient: @ingredient,
          user: current_user,
          quantity_delta: delta,
          adjustment_type: params[:adjustment_type],
          reason_notes: params[:reason_notes]
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

      def ingredient_params
        permitted = params.require(:ingredient).permit(
          :name, :ingredient_category_id, :unit, :reorder_threshold,
          :quantity_on_hand, :cost_per_unit_dollars, :active
        )
        dollars = permitted.delete(:cost_per_unit_dollars)
        permitted[:cost_per_unit_cents] = (BigDecimal(dollars.to_s.presence || "0") * 100).round
        permitted
      end
    end
  end
end
