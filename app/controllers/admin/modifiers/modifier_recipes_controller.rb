# frozen_string_literal: true

module Admin
  module Modifiers
    class ModifierRecipesController < BaseController
      before_action :set_modifier_group
      before_action :set_modifier

      def create
        authorize @modifier, :update?
        @modifier_recipe = @modifier.modifier_recipes.build(modifier_recipe_params)
        if @modifier_recipe.save
          redirect_to edit_admin_modifier_group_modifier_path(@modifier_group, @modifier),
                      notice: t("flash.modifier_recipe.added")
        else
          redirect_to edit_admin_modifier_group_modifier_path(@modifier_group, @modifier),
                      alert: @modifier_recipe.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize @modifier, :update?
        @modifier.modifier_recipes.find(params[:id]).destroy
        redirect_to edit_admin_modifier_group_modifier_path(@modifier_group, @modifier),
                    notice: t("flash.modifier_recipe.removed")
      end

      private

      def set_modifier_group
        @modifier_group = ModifierGroup.find(params[:modifier_group_id])
      end

      def set_modifier
        @modifier = @modifier_group.modifiers.find(params[:modifier_id])
      end

      def modifier_recipe_params
        params.require(:modifier_recipe).permit(:ingredient_id, :quantity, :unit)
      end
    end
  end
end
