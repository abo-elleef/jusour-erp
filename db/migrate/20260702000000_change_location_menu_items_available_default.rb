# frozen_string_literal: true

class ChangeLocationMenuItemsAvailableDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :location_menu_items, :available, from: true, to: false
  end
end
