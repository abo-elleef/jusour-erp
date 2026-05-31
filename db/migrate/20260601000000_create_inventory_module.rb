# frozen_string_literal: true

class CreateInventoryModule < ActiveRecord::Migration[7.1]
  def change
    create_table :ingredient_categories, id: :uuid do |t|
      t.string :name, null: false
      t.integer :position, default: 0
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :ingredient_categories, :name, unique: true

    create_table :ingredients, id: :uuid do |t|
      t.references :ingredient_category, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :unit, null: false
      t.decimal :reorder_threshold, null: false, precision: 10, scale: 3, default: 0
      t.decimal :quantity_on_hand, null: false, precision: 10, scale: 3, default: 0
      t.integer :cost_per_unit_cents, null: false, default: 0
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :ingredients, :name
    add_index :ingredients, :active

    create_table :suppliers, id: :uuid do |t|
      t.string :name, null: false
      t.string :contact_name
      t.string :email
      t.string :phone
      t.text :address
      t.integer :lead_time_days, default: 1
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :suppliers, :name

    create_table :recipes, id: :uuid do |t|
      t.references :menu_item, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :quantity_used, null: false, precision: 10, scale: 4
      t.timestamps
    end
    add_index :recipes, %i[menu_item_id ingredient_id], unique: true

    create_table :stock_batches, id: :uuid do |t|
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.references :supplier, type: :uuid, foreign_key: true
      t.decimal :quantity_received, null: false, precision: 10, scale: 3
      t.decimal :quantity_remaining, null: false, precision: 10, scale: 3
      t.integer :cost_per_unit_cents, null: false, default: 0
      t.date :received_on, null: false
      t.date :expires_on
      t.string :batch_reference
      t.timestamps
    end
    add_index :stock_batches, :expires_on
    add_index :stock_batches, :received_on

    create_table :stock_adjustments, id: :uuid do |t|
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :stock_batch, type: :uuid, foreign_key: true
      t.decimal :quantity_delta, null: false, precision: 10, scale: 3
      t.string :adjustment_type, null: false
      t.string :reason_notes
      t.timestamps
    end
    add_index :stock_adjustments, :adjustment_type
    add_index :stock_adjustments, :created_at

    create_table :supplier_ingredients, id: :uuid do |t|
      t.references :supplier, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.integer :price_cents, null: false, default: 0
      t.boolean :preferred, default: false
      t.timestamps
    end
    add_index :supplier_ingredients, %i[supplier_id ingredient_id], unique: true

    create_table :supplier_price_histories, id: :uuid do |t|
      t.references :supplier, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.integer :price_cents, null: false
      t.date :effective_date, null: false
      t.references :recorded_by_user, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :supplier_price_histories, %i[supplier_id ingredient_id effective_date],
              name: "index_supplier_price_histories_on_supplier_ingredient_date"

    create_table :purchase_orders, id: :uuid do |t|
      t.references :supplier, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :po_number, null: false
      t.string :status, null: false, default: "draft"
      t.date :ordered_on
      t.date :expected_on
      t.integer :total_cents, default: 0
      t.text :notes
      t.timestamps
    end
    add_index :purchase_orders, :po_number, unique: true
    add_index :purchase_orders, :status
    add_index :purchase_orders, :ordered_on

    create_table :purchase_order_items, id: :uuid do |t|
      t.references :purchase_order, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :quantity_ordered, null: false, precision: 10, scale: 3
      t.decimal :quantity_received, precision: 10, scale: 3, default: 0
      t.integer :unit_price_cents, null: false
      t.string :status, default: "pending"
      t.text :discrepancy_notes
      t.timestamps
    end

    create_table :stock_takes, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false, default: "in_progress"
      t.datetime :started_at
      t.datetime :completed_at
      t.text :notes
      t.timestamps
    end

    create_table :stock_take_items, id: :uuid do |t|
      t.references :stock_take, type: :uuid, null: false, foreign_key: true
      t.references :ingredient, type: :uuid, null: false, foreign_key: true
      t.decimal :expected_quantity, precision: 10, scale: 3
      t.decimal :counted_quantity, precision: 10, scale: 3
      t.decimal :variance, precision: 10, scale: 3
      t.boolean :adjusted, default: false
      t.timestamps
    end

    create_table :notifications, id: :uuid do |t|
      t.references :recipient, polymorphic: true, null: false, type: :uuid
      t.string :type
      t.jsonb :params
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, :read_at
  end
end
