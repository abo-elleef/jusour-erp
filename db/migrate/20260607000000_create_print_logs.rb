# frozen_string_literal: true

class CreatePrintLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :print_logs, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.references :printer, foreign_key: true, type: :uuid
      t.string :print_type, null: false, default: "receipt"
      t.string :status, null: false
      t.text :error_message

      t.timestamps
    end

    add_index :print_logs, :status
    add_index :print_logs, :print_type
  end
end
