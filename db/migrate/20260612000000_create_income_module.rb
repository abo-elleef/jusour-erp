# frozen_string_literal: true

class CreateIncomeModule < ActiveRecord::Migration[7.1]
  def change
    create_table :income_categories, id: :uuid do |t|
      t.string :name, null: false
      t.string :category_type, null: false
      t.boolean :system_managed, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :income_categories, :name, unique: true

    create_table :incomes, id: :uuid do |t|
      t.references :income_category, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :description, null: false
      t.integer :amount_cents, null: false
      t.date :income_date, null: false
      t.string :recurrence, default: "one_time", null: false
      t.string :reference_number
      t.boolean :is_auto_generated, default: false, null: false
      t.string :source_record_type
      t.uuid :source_record_id
      t.timestamps
    end
    add_index :incomes, :income_date
    add_index :incomes, :is_auto_generated
    add_index :incomes, %i[source_record_type source_record_id]
  end
end
