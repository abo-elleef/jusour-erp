# frozen_string_literal: true

class AddUnitToRecipes < ActiveRecord::Migration[7.1]
  def change
    # The unit quantity_used is expressed in. Null means the ingredient's base unit.
    add_column :recipes, :unit, :string
  end
end
