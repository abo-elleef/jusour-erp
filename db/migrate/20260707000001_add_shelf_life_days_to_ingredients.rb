# frozen_string_literal: true

class AddShelfLifeDaysToIngredients < ActiveRecord::Migration[7.1]
  def change

    add_column :ingredients, :shelf_life_days, :integer, if_not_exists: true
  end
end
