# frozen_string_literal: true

class CreateFixedAssets < ActiveRecord::Migration[7.1]
  def change
    create_table :fixed_assets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company,     null: false, foreign_key: true, type: :uuid
      t.references :location,    null: true,  foreign_key: true, type: :uuid
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }, type: :uuid

      t.string  :name,              null: false
      t.string  :asset_type,        null: false
      t.date    :purchase_date,     null: false
      t.integer :purchase_price_cents, null: false, default: 0
      t.integer :current_value_cents,  null: false, default: 0
      t.integer :useful_life_years
      t.string  :serial_number
      t.text    :notes
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :fixed_assets, [:company_id, :asset_type]
    add_index :fixed_assets, [:company_id, :active]
  end
end
