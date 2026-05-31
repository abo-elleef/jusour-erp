# frozen_string_literal: true

class CreateAccountingModule < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :hourly_rate_cents, :integer, default: 0, null: false

    create_table :expense_categories, id: :uuid do |t|
      t.string :name, null: false
      t.string :category_type, null: false
      t.boolean :system_managed, default: false, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :expense_categories, :name, unique: true

    create_table :expenses, id: :uuid do |t|
      t.references :expense_category, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :description, null: false
      t.integer :amount_cents, null: false
      t.date :expense_date, null: false
      t.string :recurrence, default: "one_time", null: false
      t.string :reference_number
      t.boolean :is_auto_generated, default: false, null: false
      t.string :source_record_type
      t.uuid :source_record_id
      t.timestamps
    end
    add_index :expenses, :expense_date
    add_index :expenses, :is_auto_generated
    add_index :expenses, %i[source_record_type source_record_id]

    create_table :budgets, id: :uuid do |t|
      t.references :expense_category, type: :uuid, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :amount_cents, null: false, default: 0
      t.timestamps
    end
    add_index :budgets, %i[expense_category_id year month], unique: true

    create_table :shift_logs, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.datetime :clocked_in_at, null: false
      t.datetime :clocked_out_at
      t.integer :break_minutes, default: 0, null: false
      t.integer :hourly_rate_cents, null: false
      t.integer :tips_cents, default: 0, null: false
      t.string :status, default: "active", null: false
      t.text :notes
      t.timestamps
    end
    add_index :shift_logs, :clocked_in_at
    add_index :shift_logs, :status

    create_table :overtime_rules, id: :uuid do |t|
      t.string :name, null: false
      t.decimal :daily_threshold_hours, precision: 4, scale: 2
      t.decimal :weekly_threshold_hours, precision: 4, scale: 2, default: 40.0
      t.decimal :ot_multiplier, precision: 3, scale: 2, default: 1.5
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    create_table :cash_drawer_sessions, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.date :session_date, null: false
      t.string :shift, null: false
      t.integer :opening_float_cents, null: false, default: 0
      t.integer :expected_cash_cents
      t.integer :counted_cash_cents
      t.integer :variance_cents
      t.string :status, default: "open", null: false
      t.text :notes
      t.timestamps
    end
    add_index :cash_drawer_sessions, %i[user_id session_date shift], unique: true

    create_table :audit_log_entries, id: :uuid do |t|
      t.references :user, type: :uuid, foreign_key: true
      t.string :action, null: false
      t.string :record_type, null: false
      t.uuid :record_id, null: false
      t.jsonb :changes_snapshot, default: {}, null: false
      t.string :ip_address
      t.timestamps
    end
    add_index :audit_log_entries, %i[record_type record_id]
    add_index :audit_log_entries, :action
    add_index :audit_log_entries, :created_at

    create_table :accounting_integrations, id: :uuid do |t|
      t.string :provider, null: false
      t.string :status, null: false, default: "disconnected"
      t.text :access_token_encrypted
      t.text :refresh_token_encrypted
      t.datetime :token_expires_at
      t.string :realm_id
      t.jsonb :account_mapping, default: {}, null: false
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
    end
    add_index :accounting_integrations, :provider, unique: true
  end
end
