# frozen_string_literal: true

class CreatePrinterMenuItems < ActiveRecord::Migration[7.1]
  def change
    create_table :printer_menu_items, id: :uuid do |t|
      t.references :printer, null: false, foreign_key: true, type: :uuid
      t.references :menu_item, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :printer_menu_items, %i[printer_id menu_item_id], unique: true
  end
end
