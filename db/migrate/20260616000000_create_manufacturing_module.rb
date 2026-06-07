# frozen_string_literal: true

class CreateManufacturingModule < ActiveRecord::Migration[7.1]
  def change
    create_table :manufacturing_templates, id: :uuid do |t|
      t.string :name, null: false
      t.references :output_ingredient, type: :uuid, null: false, foreign_key: { to_table: :ingredients }
      t.decimal :yield_quantity, precision: 10, scale: 3, null: false, default: 1
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.text :notes
      t.timestamps
    end
    add_index :manufacturing_templates, :name, unique: true
    add_index :manufacturing_templates, :active

    create_table :manufacturing_template_lines, id: :uuid do |t|
      t.references :manufacturing_template, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :quantity_used, precision: 10, scale: 3, null: false
      t.timestamps
    end
    add_index :manufacturing_template_lines,
              %i[manufacturing_template_id ingredient_id],
              unique: true,
              name: "index_mfg_template_lines_on_template_and_ingredient"

    create_table :manufacturing_runs, id: :uuid do |t|
      t.references :manufacturing_template, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.decimal :runs_count, precision: 10, scale: 3, null: false
      t.date :occurred_on, null: false
      t.text :notes
      t.timestamps
    end
    add_index :manufacturing_runs, :occurred_on
  end
end
