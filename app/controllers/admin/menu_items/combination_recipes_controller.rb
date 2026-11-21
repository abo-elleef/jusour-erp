# frozen_string_literal: true

module Admin
  module MenuItems
    # One row of a menu item's recipe matrix: "Double · Spicy uses …".
    # Customising a row saves it as a full recipe, starting from what the row
    # used before (the item recipe plus the options' own recipes).
    class CombinationRecipesController < BaseController
      before_action :set_menu_item
      before_action :set_combination_recipe, only: %i[edit copy destroy]

      def create
        authorize @menu_item, :update?
        matrix = ::Inventory::RecipeMatrix.new(@menu_item)
        row = matrix.row_for_key(params[:modifier_ids])
        return redirect_to(matrix_path, alert: t("menu.recipe_matrix.unknown_row")) unless row

        recipe = row.combination || CombinationRecipe.transaction do
          @menu_item.combination_recipes.create!(modifier_ids: row.key).tap do |created|
            matrix.starting_quantities(row.choices.filter_map(&:modifier)).each do |ingredient, quantity|
              created.lines.create!(ingredient: ingredient, quantity: quantity)
            end
          end
        end
        redirect_to edit_admin_menu_item_combination_recipe_path(@menu_item, recipe)
      end

      def edit
        authorize @menu_item, :update?
        @matrix = ::Inventory::RecipeMatrix.new(@menu_item)
        @row = @matrix.row_for_key(@combination_recipe.modifier_ids)
        @lines = @combination_recipe.lines.includes(:unit_ref, ingredient: [:unit_ref, :ingredient_units])
        @line_ingredients = Ingredient.active.includes(:ingredient_units)
          .where.not(id: @lines.map(&:ingredient_id)).order(:name)
        @copy_sources = @matrix.rows.select(&:custom?).reject { |row| row.combination == @combination_recipe }
      end

      # Replace this row's lines with another custom row's — Triple from Double, say.
      def copy
        authorize @menu_item, :update?
        source = @menu_item.combination_recipes.find(params[:source_id])
        CombinationRecipe.transaction do
          @combination_recipe.lines.destroy_all
          source.lines.each do |line|
            @combination_recipe.lines.create!(ingredient_id: line.ingredient_id, quantity: line.quantity, unit_id: line.unit_id)
          end
        end
        redirect_to edit_admin_menu_item_combination_recipe_path(@menu_item, @combination_recipe),
                    notice: t("menu.recipe_matrix.copied")
      end

      # Back to automatic: the row uses the item recipe plus the options' own again.
      def destroy
        authorize @menu_item, :update?
        @combination_recipe.destroy!
        redirect_to matrix_path, notice: t("menu.recipe_matrix.reset_done")
      end

      private

      def set_menu_item
        @menu_item = MenuItem.find(params[:menu_item_id])
      end

      def set_combination_recipe
        @combination_recipe = @menu_item.combination_recipes.find(params[:id])
      end

      def matrix_path
        edit_admin_menu_item_path(@menu_item, at: "recipe-matrix")
      end
    end
  end
end
