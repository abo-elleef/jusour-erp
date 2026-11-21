# frozen_string_literal: true

module Admin
  module MenuItems
    # The ingredient lines of one recipe matrix row. Each action answers with
    # the row's edit page; the lines sit in a Turbo Frame there, so the page
    # stays where the owner clicked.
    class CombinationRecipeLinesController < BaseController
      before_action :set_combination_recipe

      def create
        authorize @menu_item, :update?
        line = @combination_recipe.lines.build(line_params)
        flash[:alert] = line.errors.full_messages.to_sentence unless line.save
        redirect_to edit_path
      end

      def update
        authorize @menu_item, :update?
        line = @combination_recipe.lines.find(params[:id])
        flash[:alert] = line.errors.full_messages.to_sentence unless line.update(params.require(:line).permit(:quantity))
        redirect_to edit_path
      end

      def destroy
        authorize @menu_item, :update?
        @combination_recipe.lines.find(params[:id]).destroy!
        redirect_to edit_path
      end

      private

      def set_combination_recipe
        @menu_item = MenuItem.find(params[:menu_item_id])
        @combination_recipe = @menu_item.combination_recipes.find(params[:combination_recipe_id])
      end

      def line_params
        params.require(:line).permit(:ingredient_id, :quantity, :unit)
      end

      def edit_path
        edit_admin_menu_item_combination_recipe_path(@menu_item, @combination_recipe)
      end
    end
  end
end
