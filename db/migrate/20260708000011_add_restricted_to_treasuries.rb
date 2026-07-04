# frozen_string_literal: true

class AddRestrictedToTreasuries < ActiveRecord::Migration[7.1]
  def change
    add_column :treasuries, :restricted, :boolean, default: false, null: false
  end
end
