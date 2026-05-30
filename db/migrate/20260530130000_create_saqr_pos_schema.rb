# frozen_string_literal: true

class CreateSaqrPosSchema < ActiveRecord::Migration[7.1]
  def change
    create_table :categories, id: :uuid do |t|
      t.string :name, null: false
      t.integer :position
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :categories, :name, unique: true
    add_index :categories, :position

    create_table :menu_items, id: :uuid do |t|
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.text :description
      t.integer :base_price_cents, null: false
      t.string :tax_category, null: false, default: "food"
      t.boolean :available, default: true, null: false
      t.integer :position
      t.timestamps
    end
    add_index :menu_items, :available

    create_table :modifier_groups, id: :uuid do |t|
      t.references :menu_item, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.boolean :required, default: false, null: false
      t.boolean :multi_select, default: false, null: false
      t.integer :position
      t.timestamps
    end
    create_table :modifiers, id: :uuid do |t|
      t.references :modifier_group, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.integer :price_adjustment_cents, default: 0, null: false
      t.integer :position
      t.timestamps
    end
    create_table :combos, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.integer :price_cents, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    create_table :combo_items, id: :uuid do |t|
      t.references :combo, null: false, foreign_key: true, type: :uuid
      t.references :menu_item, null: false, foreign_key: true, type: :uuid
      t.integer :quantity, default: 1, null: false
      t.timestamps
    end
    create_table :tax_rates, id: :uuid do |t|
      t.string :name, null: false
      t.decimal :rate, precision: 5, scale: 4, null: false
      t.string :tax_category, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :tax_rates, :tax_category
    add_index :tax_rates, :active

    create_table :discount_rules, id: :uuid do |t|
      t.string :name, null: false
      t.string :code
      t.string :discount_type, null: false
      t.decimal :discount_value, precision: 10, scale: 2, null: false
      t.integer :minimum_order_cents, default: 0, null: false
      t.string :applies_to, null: false, default: "order"
      t.uuid :applies_to_id
      t.boolean :active, default: true, null: false
      t.datetime :expires_at
      t.integer :uses_remaining
      t.timestamps
    end
    add_index :discount_rules, :code, unique: true
    add_index :discount_rules, :active

    create_table :customers, id: :uuid do |t|
      t.string :name
      t.string :email
      t.string :phone
      t.integer :loyalty_points, default: 0, null: false
      t.integer :total_spent_cents, default: 0, null: false
      t.timestamps
    end
    add_index :customers, :email, unique: true
    add_index :customers, :phone, unique: true

    create_table :orders, id: :uuid do |t|
      t.references :customer, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :order_number, null: false
      t.string :status, null: false, default: "draft"
      t.integer :subtotal_cents
      t.integer :discount_cents, default: 0, null: false
      t.integer :tax_cents
      t.integer :tip_cents, default: 0, null: false
      t.integer :total_cents
      t.text :notes
      t.string :receipt_sent_via
      t.string :receipt_token
      t.timestamps
    end
    add_index :orders, :order_number, unique: true
    add_index :orders, :status
    add_index :orders, :created_at
    add_index :orders, :receipt_token, unique: true

    create_table :order_items, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.references :menu_item, foreign_key: true, type: :uuid
      t.references :combo, foreign_key: true, type: :uuid
      t.integer :quantity, default: 1, null: false
      t.integer :unit_price_cents, null: false
      t.text :notes
      t.timestamps
    end
    create_table :order_item_modifiers, id: :uuid do |t|
      t.references :order_item, null: false, foreign_key: true, type: :uuid
      t.references :modifier, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.integer :price_adjustment_cents, default: 0, null: false
      t.timestamps
    end
    create_table :order_discounts, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.references :discount_rule, foreign_key: true, type: :uuid
      t.string :description, null: false
      t.integer :amount_cents, null: false
      t.timestamps
    end
    create_table :payments, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.string :payment_method, null: false
      t.integer :amount_cents, null: false
      t.integer :tip_cents, default: 0, null: false
      t.string :status, null: false, default: "pending"
      t.string :stripe_payment_intent_id
      t.string :stripe_charge_id
      t.integer :refunded_amount_cents, default: 0, null: false
      t.string :refund_reason
      t.references :processed_by_user, foreign_key: { to_table: :users }, type: :uuid
      t.timestamps
    end
    add_index :payments, :status

    create_table :loyalty_transactions, id: :uuid do |t|
      t.references :customer, null: false, foreign_key: true, type: :uuid
      t.references :order, foreign_key: true, type: :uuid
      t.string :transaction_type, null: false
      t.integer :points, null: false
      t.string :description
      t.datetime :created_at, null: false
    end
    create_table :receipt_logs, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.string :delivery_method, null: false
      t.string :recipient, null: false
      t.string :status, null: false
      t.datetime :sent_at
      t.timestamps
    end
    create_table :gift_cards, id: :uuid do |t|
      t.string :code, null: false
      t.integer :balance_cents, null: false, default: 0
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :gift_cards, :code, unique: true

    create_table :order_events, id: :uuid do |t|
      t.references :order, null: false, foreign_key: true, type: :uuid
      t.string :event_type, null: false
      t.references :user, foreign_key: true, type: :uuid
      t.text :description
      t.datetime :created_at, null: false
    end
    create_table :settings, id: :uuid do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :settings, :key, unique: true
  end
end
