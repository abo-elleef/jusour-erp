# frozen_string_literal: true

class CreateInventorySnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :inventory_snapshots, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.date    :snapshot_date, null: false
      t.integer :value_cents,   null: false, default: 0
      t.string  :label
      t.timestamps
    end

    add_index :inventory_snapshots, %i[company_id snapshot_date], unique: true,
              name: "index_inventory_snapshots_on_company_and_date"
  end
end
