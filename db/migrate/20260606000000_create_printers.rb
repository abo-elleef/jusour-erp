# frozen_string_literal: true

class CreatePrinters < ActiveRecord::Migration[7.1]
  def change
    create_table :printers, id: :uuid do |t|
      t.string :name, null: false
      t.string :printer_type, null: false, default: "receipt"
      t.string :connection_type, null: false, default: "network"
      t.string :host
      t.integer :port, default: 9100
      t.string :location
      t.string :paper_width, default: "80mm"
      t.boolean :active, null: false, default: true
      t.boolean :is_default, null: false, default: false
      t.text :notes

      t.timestamps
    end

    add_index :printers, :name
    add_index :printers, :active
    add_index :printers, %i[printer_type is_default]
  end
end
