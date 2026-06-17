# frozen_string_literal: true

class AddPublicMenuEnabledToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :public_menu_enabled, :boolean, default: false, null: false
  end
end
