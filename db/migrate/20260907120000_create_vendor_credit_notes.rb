# frozen_string_literal: true

class CreateVendorCreditNotes < ActiveRecord::Migration[7.1]
  def change
    create_table :vendor_credit_notes, id: :uuid do |t|
      t.references :company,  type: :uuid, null: false, foreign_key: true
      t.references :supplier, type: :uuid, null: false, foreign_key: true
      t.references :user,     type: :uuid, null: false, foreign_key: true

      t.string  :credit_note_number, null: false
      t.date    :credit_note_date,   null: false
      t.string  :status,             null: false, default: "draft"
      t.integer :total_cents,        null: false, default: 0
      t.text    :notes

      t.timestamps
    end

    add_index :vendor_credit_notes,
      %i[company_id credit_note_number],
      unique: true,
      name: "index_vendor_credit_notes_on_company_and_number"
    add_index :vendor_credit_notes, :credit_note_date
    add_index :vendor_credit_notes, :status

    create_table :vendor_credit_note_lines, id: :uuid do |t|
      t.references :vendor_credit_note, type: :uuid, null: false, foreign_key: true
      t.references :ingredient,         type: :uuid, null: false, foreign_key: true
      t.references :unit,               type: :uuid, foreign_key: true, null: true

      t.decimal :quantity,         precision: 10, scale: 3, null: false, default: 0
      t.integer :unit_price_cents, null: false, default: 0
      t.integer :line_total_cents, null: false, default: 0
      t.integer :position,         null: false, default: 0
      t.text    :line_notes

      t.timestamps
    end
  end
end
