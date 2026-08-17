# frozen_string_literal: true

class AddPurchaseUnitToIngredientUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :ingredient_units, :purchase_unit, :boolean, default: false, null: false

    add_index :ingredient_units, :ingredient_id,
      unique: true,
      where: "purchase_unit = true",
      name: "index_ingredient_units_one_purchase_unit_per_ingredient"
  end
end
