# frozen_string_literal: true

class CreateTreasuryModule < ActiveRecord::Migration[7.1]
  def change
    create_table :treasuries, id: :uuid do |t|
      t.string :name, null: false
      t.string :treasury_type, null: false
      t.integer :balance_cents, default: 0, null: false
      t.integer :opening_balance_cents, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.boolean :is_default, default: false, null: false
      t.integer :position, default: 0, null: false
      t.text :notes
      t.timestamps
    end
    add_index :treasuries, :name, unique: true
    add_index :treasuries, :active

    create_table :treasury_transactions, id: :uuid do |t|
      t.references :treasury, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :kind, null: false
      t.string :description, null: false
      t.date :occurred_on, null: false
      t.string :source_record_type
      t.uuid :source_record_id
      t.integer :balance_after_cents, null: false
      t.timestamps
    end
    add_index :treasury_transactions, :occurred_on
    add_index :treasury_transactions, :kind
    add_index :treasury_transactions, %i[source_record_type source_record_id],
              name: "index_treasury_transactions_on_source"

    add_reference :expenses, :treasury, type: :uuid, foreign_key: true
    add_reference :incomes, :treasury, type: :uuid, foreign_key: true
    add_reference :cash_drawer_sessions, :treasury, type: :uuid, foreign_key: true
  end
end
