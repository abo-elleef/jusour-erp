# frozen_string_literal: true

module Admin
  module MenuItems
    class RecipesController < BaseController
      before_action :set_menu_item

      def create
        authorize @menu_item, :update?
        @recipe = @menu_item.recipes.build(recipe_params)
        if @recipe.save
          redirect_to edit_admin_menu_item_path(@menu_item), notice: t("flash.recipe.added")
        else
          redirect_to edit_admin_menu_item_path(@menu_item), alert: @recipe.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize @menu_item, :update?
        @menu_item.recipes.find(params[:id]).destroy
        redirect_to edit_admin_menu_item_path(@menu_item), notice: t("flash.recipe.removed")
      end

      private

      def set_menu_item
        @menu_item = MenuItem.find(params[:menu_item_id])
      end

      def recipe_params
        params.require(:recipe).permit(:ingredient_id, :quantity_used, :unit)
      end
    end
  end
end
