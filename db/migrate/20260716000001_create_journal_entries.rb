# frozen_string_literal: true

class CreateJournalEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :journal_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :company,    null: false, foreign_key: true, type: :uuid
      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string  :entry_number,  null: false
      t.date    :date,          null: false
      t.string  :description,   null: false
      t.string  :source_record_type
      t.uuid    :source_record_id
      t.string  :entry_type,    null: false, default: "auto"  # auto | manual
      t.timestamps
    end

    add_index :journal_entries, :entry_number, unique: true
    add_index :journal_entries, [ :company_id, :date ]
    add_index :journal_entries, [ :source_record_type, :source_record_id ]

    create_table :journal_entry_lines, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :journal_entry, null: false, foreign_key: true, type: :uuid
      t.references :treasury,      null: true,  foreign_key: true, type: :uuid
      t.integer :account_code,   null: false
      t.string  :account_name,   null: false
      t.string  :account_type,   null: false  # asset | liability | equity | revenue | expense
      t.integer :debit_cents,    null: false, default: 0
      t.integer :credit_cents,   null: false, default: 0
      t.string  :notes
      t.timestamps
    end

    add_index :journal_entry_lines, [ :journal_entry_id, :account_code ]
  end
end
