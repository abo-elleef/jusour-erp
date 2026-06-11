# frozen_string_literal: true

class CreateLocations < ActiveRecord::Migration[7.1]
  def change
    create_table :locations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :location_type, null: false, default: "branch"
      t.text :address
      t.string :phone
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :locations, [:company_id, :name], unique: true
    add_index :locations, :active

    create_table :ingredient_locations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :ingredient, null: false, foreign_key: true, type: :uuid
      t.references :location, null: false, foreign_key: true, type: :uuid
      t.decimal :quantity_on_hand, precision: 10, scale: 3, null: false, default: "0.0"
      t.decimal :reorder_threshold, precision: 10, scale: 3, null: false, default: "0.0"
      t.timestamps
    end

    add_index :ingredient_locations, [:ingredient_id, :location_id], unique: true

    create_table :location_menu_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :location, null: false, foreign_key: true, type: :uuid
      t.references :menu_item, null: false, foreign_key: true, type: :uuid
      t.boolean :available, null: false, default: true
      t.integer :price_override_cents
      t.timestamps
    end

    add_index :location_menu_items, [:location_id, :menu_item_id], unique: true
  end
end
