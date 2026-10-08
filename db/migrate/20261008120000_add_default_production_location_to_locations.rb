# frozen_string_literal: true

class AddDefaultProductionLocationToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :default_production_location, :boolean, default: false, null: false
  end
end
