# frozen_string_literal: true

class CreateTreasuryTransfers < ActiveRecord::Migration[7.1]
  def change
    create_table :treasury_transfers, id: :uuid do |t|
      t.references :from_treasury, type: :uuid, null: false, foreign_key: { to_table: :treasuries }
      t.references :to_treasury, type: :uuid, null: false, foreign_key: { to_table: :treasuries }
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :description, null: false
      t.date :occurred_on, null: false
      t.timestamps
    end

    add_index :treasury_transfers, :occurred_on
  end
end
