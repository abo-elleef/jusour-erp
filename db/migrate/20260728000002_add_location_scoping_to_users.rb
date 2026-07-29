# frozen_string_literal: true

class AddLocationScopingToUsers < ActiveRecord::Migration[7.1]
  def change
    # Global by default so existing users keep company-wide access; location
    # scoping is opt-in (set false + assign locations for a location manager).
    add_column :users, :all_locations, :boolean, default: true, null: false

    create_table :user_locations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :user_id, null: false
      t.uuid :location_id, null: false
      t.timestamps
    end
    add_index :user_locations, %i[user_id location_id], unique: true
    add_index :user_locations, :location_id
    add_foreign_key :user_locations, :users
    add_foreign_key :user_locations, :locations
  end
end
