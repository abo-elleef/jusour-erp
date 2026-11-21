# frozen_string_literal: true

# A recipe per combination of options ("Double · Spicy uses …"). On each menu
# item the owner ticks the option groups that change the recipe together (size
# and one other, usually); a combination with a saved recipe uses it in place of
# the item recipe and those groups' own option recipes. Untouched combinations,
# and every other group, keep working as before.
class CreateCombinationRecipes < ActiveRecord::Migration[7.1]
  def change
    add_column :menu_item_modifier_groups, :recipe_matrix, :boolean, default: false, null: false

    create_table :combination_recipes, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :menu_item, type: :uuid, null: false, foreign_key: true, index: false
      # The chosen options of the ticked groups, sorted — the combination's key.
      t.uuid :modifier_ids, array: true, null: false, default: []
      t.timestamps
    end
    add_index :combination_recipes, %i[menu_item_id modifier_ids], unique: true

    create_table :combination_recipe_lines, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :combination_recipe, type: :uuid, null: false, foreign_key: true, index: false
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, scale: 4, null: false
      t.references :unit, type: :uuid, foreign_key: true
      t.timestamps
    end
    add_index :combination_recipe_lines, %i[combination_recipe_id ingredient_id], unique: true,
      name: "index_combination_recipe_lines_on_recipe_and_ingredient"
  end
end
