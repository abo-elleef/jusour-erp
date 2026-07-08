# frozen_string_literal: true

class CreateIngredientUnits < ActiveRecord::Migration[7.1]
  def change
    create_table :ingredient_units, id: :uuid do |t|
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.string :unit, null: false
      # How many base units (the ingredient's own unit) one of THIS unit equals.
      # e.g. base = ml, unit = gallon, base_units_per_unit = 3785.
      t.decimal :base_units_per_unit, precision: 14, scale: 4, null: false

      t.timestamps
    end

    add_index :ingredient_units, %i[ingredient_id unit], unique: true
  end
end
