# frozen_string_literal: true

module Admin
  module Inventory
    class IngredientCategoriesController < BaseController
      before_action :set_category, only: %i[edit update destroy]

      def index
        authorize_inventory_index!(IngredientCategory)
        @q = IngredientCategory.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @categories = @q.result.includes(:ingredients).ordered
        @sortable = !@filtered
      end

      def reorder
        authorize_inventory!(:update)
        positions = params[:positions].presence || JSON.parse(request.body.read).fetch("positions")
        positions.each do |id, position|
          IngredientCategory.where(id: id).update_all(position: position.to_i)
        end
        head :ok
      end

      def new
        @category = IngredientCategory.new(active: true)
        authorize_inventory!(:create)
      end

      def create
        @category = IngredientCategory.new(category_params)
        authorize_inventory!(:create)
        if @category.save
          redirect_to admin_inventory_ingredient_categories_path, notice: t("flash.ingredient_category.created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize_inventory!(:update)
      end

      def update
        authorize_inventory!(:update)
        if @category.update(category_params)
          redirect_to admin_inventory_ingredient_categories_path, notice: t("flash.ingredient_category.updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize_inventory!(:destroy)
        if @category.ingredients.exists?
          redirect_to admin_inventory_ingredient_categories_path,
                      alert: t("flash.ingredient_category.cannot_delete_with_ingredients")
        else
          @category.destroy!
          redirect_to admin_inventory_ingredient_categories_path, notice: t("flash.ingredient_category.removed")
        end
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
