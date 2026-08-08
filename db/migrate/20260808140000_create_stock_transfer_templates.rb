# frozen_string_literal: true

class CreateStockTransferTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :stock_transfer_templates, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.text :notes
      t.references :default_from_location, type: :uuid, foreign_key: { to_table: :locations }
      t.references :default_to_location, type: :uuid, foreign_key: { to_table: :locations }
      t.timestamps
    end
    add_index :stock_transfer_templates, %i[company_id name], unique: true
    add_index :stock_transfer_templates, %i[company_id active]

    create_table :stock_transfer_template_lines, id: :uuid do |t|
      t.references :stock_transfer_template, type: :uuid, null: false, foreign_key: true,
                   index: { name: "index_st_template_lines_on_template_id" }
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :default_quantity, precision: 10, scale: 3, null: false, default: 0
      t.references :unit, type: :uuid, foreign_key: true
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :stock_transfer_template_lines,
              %i[stock_transfer_template_id ingredient_id],
              unique: true,
              name: "index_st_template_lines_on_template_and_ingredient"
  end
end
