# frozen_string_literal: true

module Admin
  module Inventory
    class IngredientCategoriesController < BaseController
      before_action :set_category, only: %i[edit update destroy count_sheet]

      def index
        authorize_inventory_index!(IngredientCategory)
        @q = IngredientCategory.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @categories = @q.result.includes(:ingredients).ordered
        # Drag-to-reorder writes positions, so it needs the same key the
        # reorder action is gated on.
        @sortable = !@filtered && current_user.can?("inventory:settings")
      end

      def reorder
        authorize_inventory!(:manage_settings)
        positions = params[:positions].presence || JSON.parse(request.body.read).fetch("positions")
        positions.each do |id, position|
          IngredientCategory.where(id: id).update_all(position: position.to_i)
        end
        head :ok
      end

      def new
        @category = IngredientCategory.new(active: true)
        authorize_inventory!(:manage_settings)
      end

      def create
        @category = IngredientCategory.new(category_params)
        authorize_inventory!(:manage_settings)
        if @category.save
          redirect_to admin_inventory_ingredient_categories_path, notice: t("flash.ingredient_category.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:manage_settings)
        @audits = @category.audits.includes(:user).reorder(version: :desc)
      end

      def update
        authorize_inventory!(:manage_settings)
        if @category.update(category_params)
          redirect_to admin_inventory_ingredient_categories_path, notice: t("flash.ingredient_category.updated")
        else
          @audits = @category.audits.includes(:user).reorder(version: :desc)
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:manage_settings)
        if @category.ingredients.exists?
          redirect_to admin_inventory_ingredient_categories_path,
                      alert: t("flash.ingredient_category.cannot_delete_with_ingredients")
        else
          @category.destroy!
          redirect_to admin_inventory_ingredient_categories_path, notice: t("flash.ingredient_category.removed")
        end
      end

      # Printable blind count sheet for this category across every vendor. Same
      # rationale as the vendor sheet: only one stock take can be active per
      # location, so printing has to be possible without starting one.
      def count_sheet
        authorize_inventory!(:show)
        @filter_locations = Location.active.ordered.where(id: current_user.accessible_location_ids)
        @stock_location = @filter_locations.find_by(id: params[:location_id]) if params[:location_id].present?
        # Blind by default: showing the expected balance invites confirming the
        # number instead of counting it.
        @show_balance = params[:show_balance] == "1"
        @count_sheet_groups = ::Inventory::CountSheet.new(
          location: @stock_location,
          category: @category
        ).call
        @count_sheet_row_count = @count_sheet_groups.sum { |_, rows| rows.size }
      end

      private

      def set_category
        @category = IngredientCategory.find(params[:id])
      end

      def category_params
        params.require(:ingredient_category).permit(:name, :position, :active)
      end

      def record_for_policy
        @ingredient_category || @category || IngredientCategory.new
      end
    end
  end
end
