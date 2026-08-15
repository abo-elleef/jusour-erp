# frozen_string_literal: true

class AddMaxQuantityToIngredients < ActiveRecord::Migration[7.1]
  def change
    add_column :ingredients, :max_quantity, :decimal, precision: 10, scale: 3, null: false, default: "0.0"
    add_column :ingredient_locations, :max_quantity, :decimal, precision: 10, scale: 3, null: false, default: "0.0"
  end
end
