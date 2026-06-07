# frozen_string_literal: true

class AddMultiTenancy < ActiveRecord::Migration[7.1]
  TENANT_TABLES = %w[
    users categories menu_items combos modifier_groups modifiers customers
    discount_rules gift_cards orders settings tax_rates ingredient_categories
    ingredients suppliers purchase_orders stock_takes manufacturing_templates
    expense_categories income_categories treasuries accounting_integrations
    overtime_rules printers audit_log_entries notifications
  ].freeze

  def up
    create_table :companies, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :timezone, null: false, default: "UTC"
      t.string :currency, null: false, default: "USD"
      t.string :locale, null: false, default: "en"
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :companies, :slug, unique: true

    TENANT_TABLES.each do |table|
      add_reference table, :company, type: :uuid, foreign_key: true, null: true
    end

    default_company_id = insert_default_company

    TENANT_TABLES.each do |table|
      execute <<~SQL.squish
        UPDATE #{table} SET company_id = '#{default_company_id}'
      SQL
      change_column_null table, :company_id, false
    end

    replace_unique_indexes
  end

  def down
    restore_unique_indexes

    TENANT_TABLES.reverse_each do |table|
      remove_reference table, :company, type: :uuid, foreign_key: true
    end

    drop_table :companies
  end

  private

  def insert_default_company
    execute <<~SQL.squish
      INSERT INTO companies (id, name, slug, timezone, currency, locale, active, created_at, updated_at)
      VALUES (gen_random_uuid(), 'Default Restaurant', 'default', 'UTC', 'USD', 'en', true, NOW(), NOW())
    SQL
    select_value("SELECT id FROM companies WHERE slug = 'default'")
  end

  def replace_unique_indexes
    remove_index :accounting_integrations, :provider
    add_index :accounting_integrations, %i[company_id provider], unique: true

    remove_index :categories, :name
    add_index :categories, %i[company_id name], unique: true

    remove_index :customers, :email
    add_index :customers, %i[company_id email], unique: true, where: "email IS NOT NULL AND email <> ''"

    remove_index :customers, :phone
    add_index :customers, %i[company_id phone], unique: true, where: "phone IS NOT NULL AND phone <> ''"

    remove_index :customers, :phone_secondary
    add_index :customers, %i[company_id phone_secondary], unique: true, where: "phone_secondary IS NOT NULL"

    remove_index :discount_rules, :code
    add_index :discount_rules, %i[company_id code], unique: true, where: "code IS NOT NULL"

    remove_index :expense_categories, :name
    add_index :expense_categories, %i[company_id name], unique: true

    remove_index :gift_cards, :code
    add_index :gift_cards, %i[company_id code], unique: true

    remove_index :income_categories, :name
    add_index :income_categories, %i[company_id name], unique: true

    remove_index :ingredient_categories, :name
    add_index :ingredient_categories, %i[company_id name], unique: true

    add_index :ingredients, %i[company_id name], unique: true

    remove_index :manufacturing_templates, :name
    add_index :manufacturing_templates, %i[company_id name], unique: true

    remove_index :orders, :order_number
    add_index :orders, %i[company_id order_number], unique: true

    remove_index :orders, :receipt_token
    add_index :orders, :receipt_token, unique: true

    remove_index :purchase_orders, :po_number
    add_index :purchase_orders, %i[company_id po_number], unique: true

    remove_index :settings, :key
    add_index :settings, %i[company_id key], unique: true

    remove_index :treasuries, :name
    add_index :treasuries, %i[company_id name], unique: true

    remove_index :users, :email
    add_index :users, %i[company_id email], unique: true
  end

  def restore_unique_indexes
    remove_index :accounting_integrations, column: %i[company_id provider]
    add_index :accounting_integrations, :provider, unique: true

    remove_index :categories, column: %i[company_id name]
    add_index :categories, :name, unique: true

    remove_index :customers, column: %i[company_id email]
    add_index :customers, :email, unique: true

    remove_index :customers, column: %i[company_id phone]
    add_index :customers, :phone, unique: true

    remove_index :customers, column: %i[company_id phone_secondary]
    add_index :customers, :phone_secondary, unique: true, where: "phone_secondary IS NOT NULL"

    remove_index :discount_rules, column: %i[company_id code]
    add_index :discount_rules, :code, unique: true

    remove_index :expense_categories, column: %i[company_id name]
    add_index :expense_categories, :name, unique: true

    remove_index :gift_cards, column: %i[company_id code]
    add_index :gift_cards, :code, unique: true

    remove_index :income_categories, column: %i[company_id name]
    add_index :income_categories, :name, unique: true

    remove_index :ingredient_categories, column: %i[company_id name]
    add_index :ingredient_categories, :name, unique: true

    remove_index :ingredients, column: %i[company_id name]

    remove_index :manufacturing_templates, column: %i[company_id name]
    add_index :manufacturing_templates, :name, unique: true

    remove_index :orders, column: %i[company_id order_number]
    add_index :orders, :order_number, unique: true

    remove_index :orders, :receipt_token
    add_index :orders, :receipt_token, unique: true

    remove_index :purchase_orders, column: %i[company_id po_number]
    add_index :purchase_orders, :po_number, unique: true

    remove_index :settings, column: %i[company_id key]
    add_index :settings, :key, unique: true

    remove_index :treasuries, column: %i[company_id name]
    add_index :treasuries, :name, unique: true

    remove_index :users, column: %i[company_id email]
    add_index :users, :email, unique: true
  end
end
