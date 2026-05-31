# frozen_string_literal: true

module Admin
  module Inventory
    class RecipesController < BaseController
      before_action :set_ingredient

      def create
        authorize_inventory!(:update)
        @recipe = @ingredient.recipes.build(recipe_params)
        if @recipe.save
          redirect_to admin_inventory_ingredient_path(@ingredient), notice: t("flash.recipe.added")
        else
          redirect_to admin_inventory_ingredient_path(@ingredient), alert: @recipe.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize_inventory!(:update)
        @ingredient.recipes.find(params[:id]).destroy
        redirect_to admin_inventory_ingredient_path(@ingredient), notice: t("flash.recipe.removed")
      end

      private

      def set_ingredient
        @ingredient = Ingredient.find(params[:ingredient_id])
      end

      def recipe_params
        params.require(:recipe).permit(:menu_item_id, :quantity_used)
      end
    end
  end
end
