# frozen_string_literal: true

class CreateStockTransfers < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_transfers, id: :uuid do |t|
      t.references :company, null: false, foreign_key: true, type: :uuid
      t.references :from_location, null: false, foreign_key: { to_table: :locations }, type: :uuid
      t.references :to_location, null: false, foreign_key: { to_table: :locations }, type: :uuid
      t.references :requested_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.references :sent_by, foreign_key: { to_table: :users }, type: :uuid
      t.references :received_by, foreign_key: { to_table: :users }, type: :uuid
      t.string :transfer_number, null: false
      t.string :status, null: false, default: "requested"
      t.text :notes
      t.datetime :requested_at, null: false
      t.datetime :sent_at
      t.datetime :received_at
      t.timestamps
    end

    add_index :stock_transfers, %i[company_id transfer_number], unique: true
    add_index :stock_transfers, :status

    create_table :stock_transfer_lines, id: :uuid do |t|
      t.references :stock_transfer, null: false, foreign_key: true, type: :uuid
      t.references :ingredient, null: false, foreign_key: true, type: :uuid
      t.decimal :quantity_requested, null: false, precision: 10, scale: 3, default: "0.0"
      t.decimal :quantity_sent, precision: 10, scale: 3
      t.decimal :quantity_received, precision: 10, scale: 3
      t.timestamps
    end

    add_index :stock_transfer_lines, %i[stock_transfer_id ingredient_id], unique: true

    add_reference :stock_adjustments, :stock_transfer, foreign_key: true, type: :uuid
  end
end
