# frozen_string_literal: true

# Step 2 slice 4: customer credit notes / sales returns. Confirming one reduces
# the customer's AR balance (Dr Sales Revenue / Cr AR) and, when restock is on,
# returns the goods to inventory.
class CreateCreditNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :credit_notes, id: :uuid do |t|
      t.references :company,  type: :uuid, null: false, index: true
      t.references :customer, type: :uuid, null: false, index: true
      t.references :user,     type: :uuid, null: false, index: true
      t.references :location, type: :uuid, null: false, index: true
      # Optional reference to the invoice being credited; when present, the credit
      # is applied against that invoice's balance.
      t.references :customer_invoice, type: :uuid, null: true, index: true
      t.string  :credit_note_number, null: false
      t.date    :credit_note_date, null: false
      t.string  :status, default: "draft", null: false
      t.boolean :restock, default: true, null: false
      t.bigint  :total_cents, default: 0, null: false
      t.datetime :confirmed_at
      t.text    :notes
      t.timestamps
    end
    add_index :credit_notes, %i[company_id credit_note_number], unique: true

    create_table :credit_note_lines, id: :uuid do |t|
      t.references :credit_note, type: :uuid, null: false, index: true
      t.references :ingredient, type: :uuid, null: false, index: true
      t.uuid    :unit_id
      t.decimal :quantity, precision: 12, scale: 3, null: false
      t.bigint  :unit_price_cents, default: 0, null: false
      t.bigint  :line_total_cents, default: 0, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
  end
end
