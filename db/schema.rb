# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_08_15_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "accounting_integrations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "provider", null: false
    t.string "status", default: "disconnected", null: false
    t.text "access_token_encrypted"
    t.text "refresh_token_encrypted"
    t.datetime "token_expires_at"
    t.string "realm_id"
    t.jsonb "account_mapping", default: {}, null: false
    t.datetime "last_synced_at"
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id", "provider"], name: "index_accounting_integrations_on_company_id_and_provider", unique: true
    t.index ["company_id"], name: "index_accounting_integrations_on_company_id"
  end

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "attendance_statuses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "code", null: false
    t.string "symbol", null: false
    t.string "label", null: false
    t.decimal "paid_fraction", precision: 4, scale: 2, default: "1.0", null: false
    t.decimal "penalty_days", precision: 4, scale: 2, default: "0.0", null: false
    t.string "color"
    t.integer "position", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "bonus_days", precision: 4, scale: 2, default: "0.0", null: false
    t.index ["company_id", "code"], name: "index_attendance_statuses_on_company_id_and_code", unique: true
    t.index ["company_id", "symbol"], name: "index_attendance_statuses_on_company_id_and_symbol", unique: true
    t.index ["company_id"], name: "index_attendance_statuses_on_company_id"
  end

  create_table "audit_log_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "action", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.jsonb "changes_snapshot", default: {}, null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["action"], name: "index_audit_log_entries_on_action"
    t.index ["company_id"], name: "index_audit_log_entries_on_company_id"
    t.index ["created_at"], name: "index_audit_log_entries_on_created_at"
    t.index ["record_type", "record_id"], name: "index_audit_log_entries_on_record_type_and_record_id"
    t.index ["user_id"], name: "index_audit_log_entries_on_user_id"
  end

  create_table "audits", force: :cascade do |t|
    t.uuid "auditable_id"
    t.string "auditable_type"
    t.uuid "associated_id"
    t.string "associated_type"
    t.uuid "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.jsonb "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at"
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "budgets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "expense_category_id", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_budgets_on_company_id"
    t.index ["expense_category_id", "year", "month"], name: "index_budgets_on_expense_category_id_and_year_and_month", unique: true
    t.index ["expense_category_id"], name: "index_budgets_on_expense_category_id"
  end

  create_table "cash_drawer_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.date "session_date", null: false
    t.integer "opening_float_cents", default: 0, null: false
    t.integer "expected_cash_cents"
    t.integer "counted_cash_cents"
    t.integer "variance_cents"
    t.string "status", default: "open", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "treasury_id"
    t.uuid "location_id"
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_cash_drawer_sessions_on_company_id"
    t.index ["location_id"], name: "index_cash_drawer_sessions_on_location_id"
    t.index ["treasury_id"], name: "index_cash_drawer_sessions_on_treasury_id"
    t.index ["user_id"], name: "index_cash_drawer_sessions_on_user_id"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.integer "position"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.string "code", null: false
    t.index "company_id, lower((code)::text)", name: "index_categories_on_company_and_lower_code", unique: true
    t.index ["company_id", "name"], name: "index_categories_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_categories_on_company_id"
    t.index ["position"], name: "index_categories_on_position"
  end

  create_table "combo_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "combo_id", null: false
    t.uuid "menu_item_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["combo_id"], name: "index_combo_items_on_combo_id"
    t.index ["menu_item_id"], name: "index_combo_items_on_menu_item_id"
  end

  create_table "combos", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "price_cents", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.datetime "starts_at"
    t.datetime "ends_at"
    t.boolean "highlight", default: false, null: false
    t.index ["company_id"], name: "index_combos_on_company_id"
  end

  create_table "companies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "timezone", default: "UTC", null: false
    t.string "currency", default: "USD", null: false
    t.string "locale", default: "en", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "company_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.integer "loyalty_earn_rate", default: 1, null: false
    t.integer "loyalty_redeem_threshold", default: 100, null: false
    t.integer "loyalty_redeem_value_cents", default: 500, null: false
    t.string "restaurant_name"
    t.string "print_routing", default: "client", null: false
    t.integer "print_agent_port", default: 9310, null: false
    t.string "print_agent_token", default: "", null: false
    t.string "print_encoding", default: "utf-8", null: false
    t.integer "print_code_page", default: 22, null: false
    t.string "arabic_font_path", default: "", null: false
    t.string "receipt_logo_url", default: "", null: false
    t.text "receipt_footer_text", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "business_day_start_hour", default: 6, null: false
    t.string "business_day_mode", default: "automatic", null: false
    t.boolean "restrict_stock_transfers_to_source", default: true, null: false
    t.index ["company_id"], name: "index_company_settings_on_company_id", unique: true
  end

  create_table "customer_addresses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.string "label"
    t.text "address", null: false
    t.boolean "is_default", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_customer_addresses_on_customer_id"
  end

  create_table "customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.integer "loyalty_points", default: 0, null: false
    t.integer "total_spent_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "phone_secondary"
    t.uuid "company_id", null: false
    t.index ["company_id", "email"], name: "index_customers_on_company_id_and_email", unique: true, where: "((email IS NOT NULL) AND ((email)::text <> ''::text))"
    t.index ["company_id", "phone"], name: "index_customers_on_company_id_and_phone", unique: true, where: "((phone IS NOT NULL) AND ((phone)::text <> ''::text))"
    t.index ["company_id", "phone_secondary"], name: "index_customers_on_company_id_and_phone_secondary", unique: true, where: "(phone_secondary IS NOT NULL)"
    t.index ["company_id"], name: "index_customers_on_company_id"
  end

  create_table "digital_wallet_day_closes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.date "business_date", null: false
    t.integer "instapay_statement_cents", default: 0, null: false
    t.integer "vodafone_cash_statement_cents", default: 0, null: false
    t.text "notes"
    t.uuid "recorded_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "location_id"
    t.index ["company_id", "business_date", "location_id"], name: "index_digital_wallet_day_closes_on_company_date_location", unique: true
    t.index ["company_id"], name: "index_digital_wallet_day_closes_on_company_id"
    t.index ["location_id"], name: "index_digital_wallet_day_closes_on_location_id"
    t.index ["recorded_by_id"], name: "index_digital_wallet_day_closes_on_recorded_by_id"
  end

  create_table "discount_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "code"
    t.string "discount_type", null: false
    t.decimal "discount_value", precision: 10, scale: 2, null: false
    t.integer "minimum_order_cents", default: 0, null: false
    t.string "applies_to", default: "order", null: false
    t.uuid "applies_to_id"
    t.boolean "active", default: true, null: false
    t.datetime "expires_at"
    t.integer "uses_remaining"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["active"], name: "index_discount_rules_on_active"
    t.index ["company_id", "code"], name: "index_discount_rules_on_company_id_and_code", unique: true, where: "(code IS NOT NULL)"
    t.index ["company_id"], name: "index_discount_rules_on_company_id"
  end

  create_table "expense_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "category_type", null: false
    t.boolean "system_managed", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.integer "account_code", null: false
    t.index ["company_id", "account_code"], name: "index_expense_categories_on_company_id_and_account_code", unique: true
    t.index ["company_id", "name"], name: "index_expense_categories_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_expense_categories_on_company_id"
  end

  create_table "expenses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "expense_category_id", null: false
    t.uuid "user_id", null: false
    t.string "description", null: false
    t.integer "amount_cents", null: false
    t.date "expense_date", null: false
    t.string "recurrence", default: "one_time", null: false
    t.string "reference_number"
    t.boolean "is_auto_generated", default: false, null: false
    t.string "source_record_type"
    t.uuid "source_record_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "treasury_id"
    t.uuid "company_id", null: false
    t.datetime "reversed_at"
    t.index ["company_id"], name: "index_expenses_on_company_id"
    t.index ["expense_category_id"], name: "index_expenses_on_expense_category_id"
    t.index ["expense_date"], name: "index_expenses_on_expense_date"
    t.index ["is_auto_generated"], name: "index_expenses_on_is_auto_generated"
    t.index ["reversed_at"], name: "index_expenses_on_reversed_at"
    t.index ["source_record_type", "source_record_id"], name: "index_expenses_on_source_record_type_and_source_record_id"
    t.index ["treasury_id"], name: "index_expenses_on_treasury_id"
    t.index ["user_id"], name: "index_expenses_on_user_id"
  end

  create_table "fixed_assets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "location_id"
    t.uuid "recorded_by_id", null: false
    t.string "name", null: false
    t.string "asset_type", null: false
    t.date "purchase_date", null: false
    t.integer "purchase_price_cents", default: 0, null: false
    t.integer "current_value_cents", default: 0, null: false
    t.integer "useful_life_years"
    t.string "serial_number"
    t.text "notes"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "active"], name: "index_fixed_assets_on_company_id_and_active"
    t.index ["company_id", "asset_type"], name: "index_fixed_assets_on_company_id_and_asset_type"
    t.index ["company_id"], name: "index_fixed_assets_on_company_id"
    t.index ["location_id"], name: "index_fixed_assets_on_location_id"
    t.index ["recorded_by_id"], name: "index_fixed_assets_on_recorded_by_id"
  end

  create_table "gift_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", null: false
    t.integer "balance_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id", "code"], name: "index_gift_cards_on_company_id_and_code", unique: true
    t.index ["company_id"], name: "index_gift_cards_on_company_id"
  end

  create_table "income_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "category_type", null: false
    t.boolean "system_managed", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.integer "account_code", null: false
    t.index ["company_id", "account_code"], name: "index_income_categories_on_company_id_and_account_code", unique: true
    t.index ["company_id", "name"], name: "index_income_categories_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_income_categories_on_company_id"
  end

  create_table "incomes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "income_category_id", null: false
    t.uuid "user_id", null: false
    t.string "description", null: false
    t.integer "amount_cents", null: false
    t.date "income_date", null: false
    t.string "recurrence", default: "one_time", null: false
    t.string "reference_number"
    t.boolean "is_auto_generated", default: false, null: false
    t.string "source_record_type"
    t.uuid "source_record_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "treasury_id"
    t.uuid "company_id", null: false
    t.datetime "reversed_at"
    t.index ["company_id"], name: "index_incomes_on_company_id"
    t.index ["income_category_id"], name: "index_incomes_on_income_category_id"
    t.index ["income_date"], name: "index_incomes_on_income_date"
    t.index ["is_auto_generated"], name: "index_incomes_on_is_auto_generated"
    t.index ["reversed_at"], name: "index_incomes_on_reversed_at"
    t.index ["source_record_type", "source_record_id"], name: "index_incomes_on_source_record_type_and_source_record_id"
    t.index ["treasury_id"], name: "index_incomes_on_treasury_id"
    t.index ["user_id"], name: "index_incomes_on_user_id"
  end

  create_table "ingredient_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.integer "position", default: 0
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.string "code", null: false
    t.index "company_id, lower((code)::text)", name: "index_ingredient_categories_on_company_and_lower_code", unique: true
    t.index ["company_id", "name"], name: "index_ingredient_categories_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_ingredient_categories_on_company_id"
  end

  create_table "ingredient_locations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ingredient_id", null: false
    t.uuid "location_id", null: false
    t.decimal "quantity_on_hand", precision: 10, scale: 3, default: "0.0", null: false
    t.decimal "reorder_threshold", precision: 10, scale: 3, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "max_quantity", precision: 10, scale: 3, default: "0.0", null: false
    t.index ["ingredient_id", "location_id"], name: "index_ingredient_locations_on_ingredient_id_and_location_id", unique: true
    t.index ["ingredient_id"], name: "index_ingredient_locations_on_ingredient_id"
    t.index ["location_id"], name: "index_ingredient_locations_on_location_id"
  end

  create_table "ingredient_units", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ingredient_id", null: false
    t.uuid "company_id", null: false
    t.decimal "base_units_per_unit", precision: 14, scale: 4, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "unit_id", null: false
    t.index ["company_id"], name: "index_ingredient_units_on_company_id"
    t.index ["ingredient_id"], name: "index_ingredient_units_on_ingredient_id"
    t.index ["unit_id"], name: "index_ingredient_units_on_unit_id"
  end

  create_table "ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ingredient_category_id", null: false
    t.string "name", null: false
    t.decimal "reorder_threshold", precision: 10, scale: 3, default: "0.0", null: false
    t.decimal "quantity_on_hand", precision: 10, scale: 3, default: "0.0", null: false
    t.integer "cost_per_unit_cents", default: 0, null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.integer "shelf_life_days"
    t.uuid "unit_id", null: false
    t.string "code", null: false
    t.decimal "max_quantity", precision: 10, scale: 3, default: "0.0", null: false
    t.index "company_id, lower((code)::text)", name: "index_ingredients_on_company_and_lower_code", unique: true
    t.index ["active"], name: "index_ingredients_on_active"
    t.index ["company_id", "name"], name: "index_ingredients_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_ingredients_on_company_id"
    t.index ["ingredient_category_id"], name: "index_ingredients_on_ingredient_category_id"
    t.index ["name"], name: "index_ingredients_on_name"
    t.index ["unit_id"], name: "index_ingredients_on_unit_id"
  end

  create_table "journal_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "created_by_id", null: false
    t.string "entry_number", null: false
    t.date "date", null: false
    t.string "description", null: false
    t.string "source_record_type"
    t.uuid "source_record_id"
    t.string "entry_type", default: "auto", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "reversal_of_id"
    t.index ["company_id", "date"], name: "index_journal_entries_on_company_id_and_date"
    t.index ["company_id"], name: "index_journal_entries_on_company_id"
    t.index ["created_by_id"], name: "index_journal_entries_on_created_by_id"
    t.index ["entry_number"], name: "index_journal_entries_on_entry_number", unique: true
    t.index ["reversal_of_id"], name: "index_journal_entries_on_reversal_of_id"
    t.index ["source_record_type", "source_record_id"], name: "idx_on_source_record_type_source_record_id_459d508040"
  end

  create_table "journal_entry_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "journal_entry_id", null: false
    t.uuid "treasury_id"
    t.integer "account_code", null: false
    t.string "account_name", null: false
    t.string "account_type", null: false
    t.integer "debit_cents", default: 0, null: false
    t.integer "credit_cents", default: 0, null: false
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["journal_entry_id", "account_code"], name: "index_journal_entry_lines_on_journal_entry_id_and_account_code"
    t.index ["journal_entry_id"], name: "index_journal_entry_lines_on_journal_entry_id"
    t.index ["treasury_id"], name: "index_journal_entry_lines_on_treasury_id"
  end

  create_table "loans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "loan_type", default: "bank_loan", null: false
    t.integer "account_code", null: false
    t.bigint "principal_cents", default: 0, null: false
    t.decimal "interest_rate", precision: 5, scale: 2, default: "0.0"
    t.date "disbursement_date"
    t.date "due_date"
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "account_code"], name: "index_loans_on_company_id_and_account_code", unique: true
    t.index ["company_id"], name: "index_loans_on_company_id"
  end

  create_table "location_menu_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "location_id", null: false
    t.uuid "menu_item_id", null: false
    t.boolean "available", default: false, null: false
    t.integer "price_override_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "menu_item_id"], name: "index_location_menu_items_on_location_id_and_menu_item_id", unique: true
    t.index ["location_id"], name: "index_location_menu_items_on_location_id"
    t.index ["menu_item_id"], name: "index_location_menu_items_on_menu_item_id"
  end

  create_table "location_operating_days", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "location_id", null: false
    t.date "business_date", null: false
    t.datetime "opened_at", null: false
    t.uuid "opened_by_id"
    t.datetime "closed_at"
    t.uuid "closed_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["closed_by_id"], name: "index_location_operating_days_on_closed_by_id"
    t.index ["company_id", "location_id", "business_date"], name: "idx_on_company_id_location_id_business_date_e26ae21c0d"
    t.index ["company_id"], name: "index_location_operating_days_on_company_id"
    t.index ["location_id"], name: "index_location_operating_days_on_location_id"
    t.index ["location_id"], name: "index_location_operating_days_one_open_per_location", unique: true, where: "(closed_at IS NULL)"
    t.index ["opened_by_id"], name: "index_location_operating_days_on_opened_by_id"
  end

  create_table "locations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "location_type", default: "branch", null: false
    t.text "address"
    t.string "phone"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug", null: false
    t.boolean "public_menu_enabled", default: false, null: false
    t.string "whatsapp_number"
    t.integer "business_day_start_hour"
    t.string "business_day_mode", default: "automatic", null: false
    t.index ["active"], name: "index_locations_on_active"
    t.index ["company_id", "name"], name: "index_locations_on_company_id_and_name", unique: true
    t.index ["company_id", "slug"], name: "index_locations_on_company_id_and_slug", unique: true
    t.index ["company_id"], name: "index_locations_on_company_id"
  end

  create_table "loyalty_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id", null: false
    t.uuid "order_id"
    t.string "transaction_type", null: false
    t.integer "points", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.index ["customer_id"], name: "index_loyalty_transactions_on_customer_id"
    t.index ["order_id"], name: "index_loyalty_transactions_on_order_id"
  end

  create_table "manufacturing_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "manufacturing_template_id", null: false
    t.uuid "user_id", null: false
    t.decimal "runs_count", precision: 10, scale: 3, null: false
    t.date "occurred_on", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "location_id"
    t.integer "shelf_life_days", null: false
    t.uuid "company_id", null: false
    t.string "run_number", null: false
    t.decimal "main_input_quantity", precision: 10, scale: 3
    t.uuid "main_input_unit_id"
    t.datetime "reversed_at"
    t.uuid "reversed_by_id"
    t.index ["company_id", "run_number"], name: "index_manufacturing_runs_on_company_id_and_run_number", unique: true
    t.index ["company_id"], name: "index_manufacturing_runs_on_company_id"
    t.index ["location_id"], name: "index_manufacturing_runs_on_location_id"
    t.index ["main_input_unit_id"], name: "index_manufacturing_runs_on_main_input_unit_id"
    t.index ["manufacturing_template_id"], name: "index_manufacturing_runs_on_manufacturing_template_id"
    t.index ["occurred_on"], name: "index_manufacturing_runs_on_occurred_on"
    t.index ["reversed_at"], name: "index_manufacturing_runs_on_reversed_at"
    t.index ["reversed_by_id"], name: "index_manufacturing_runs_on_reversed_by_id"
    t.index ["user_id"], name: "index_manufacturing_runs_on_user_id"
  end

  create_table "manufacturing_template_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "manufacturing_template_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "quantity_used", precision: 10, scale: 3, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "unit_id"
    t.index ["ingredient_id"], name: "index_manufacturing_template_lines_on_ingredient_id"
    t.index ["manufacturing_template_id", "ingredient_id"], name: "index_mfg_template_lines_on_template_and_ingredient", unique: true
    t.index ["manufacturing_template_id"], name: "idx_on_manufacturing_template_id_0bc4795371"
    t.index ["unit_id"], name: "index_manufacturing_template_lines_on_unit_id"
  end

  create_table "manufacturing_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.uuid "output_ingredient_id", null: false
    t.decimal "yield_quantity", precision: 10, scale: 3, default: "1.0", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.uuid "yield_unit_id"
    t.string "control_mode", default: "runs", null: false
    t.uuid "main_ingredient_id"
    t.index ["active"], name: "index_manufacturing_templates_on_active"
    t.index ["company_id", "name"], name: "index_manufacturing_templates_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_manufacturing_templates_on_company_id"
    t.index ["main_ingredient_id"], name: "index_manufacturing_templates_on_main_ingredient_id"
    t.index ["output_ingredient_id"], name: "index_manufacturing_templates_on_output_ingredient_id"
    t.index ["yield_unit_id"], name: "index_manufacturing_templates_on_yield_unit_id"
  end

  create_table "menu_item_modifier_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "menu_item_id", null: false
    t.uuid "modifier_group_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id", "modifier_group_id"], name: "index_menu_item_modifier_groups_unique", unique: true
    t.index ["menu_item_id"], name: "index_menu_item_modifier_groups_on_menu_item_id"
    t.index ["modifier_group_id"], name: "index_menu_item_modifier_groups_on_modifier_group_id"
  end

  create_table "menu_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "category_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "base_price_cents", null: false
    t.string "tax_category", default: "food", null: false
    t.boolean "available", default: true, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.string "code", null: false
    t.index "company_id, lower((code)::text)", name: "index_menu_items_on_company_and_lower_code", unique: true
    t.index ["available"], name: "index_menu_items_on_available"
    t.index ["category_id"], name: "index_menu_items_on_category_id"
    t.index ["company_id"], name: "index_menu_items_on_company_id"
  end

  create_table "menu_promos", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "menu_item_id", null: false
    t.uuid "location_id"
    t.string "name", null: false
    t.integer "promo_price_cents", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.boolean "highlight", default: true, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "starts_at", "ends_at"], name: "index_menu_promos_on_company_id_and_starts_at_and_ends_at"
    t.index ["company_id"], name: "index_menu_promos_on_company_id"
    t.index ["location_id"], name: "index_menu_promos_on_location_id"
    t.index ["menu_item_id", "starts_at", "ends_at"], name: "index_menu_promos_on_menu_item_id_and_starts_at_and_ends_at"
    t.index ["menu_item_id"], name: "index_menu_promos_on_menu_item_id"
  end

  create_table "modifier_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.boolean "required", default: false, null: false
    t.boolean "multi_select", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_modifier_groups_on_company_id"
  end

  create_table "modifier_recipes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "modifier_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "quantity", precision: 10, scale: 4, null: false
    t.uuid "company_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_modifier_recipes_on_company_id"
    t.index ["ingredient_id"], name: "index_modifier_recipes_on_ingredient_id"
    t.index ["modifier_id", "ingredient_id"], name: "index_modifier_recipes_on_modifier_id_and_ingredient_id", unique: true
    t.index ["modifier_id"], name: "index_modifier_recipes_on_modifier_id"
  end

  create_table "modifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "modifier_group_id", null: false
    t.string "name", null: false
    t.integer "price_adjustment_cents", default: 0, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_modifiers_on_company_id"
    t.index ["modifier_group_id"], name: "index_modifiers_on_modifier_group_id"
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "recipient_type", null: false
    t.uuid "recipient_id", null: false
    t.string "notification_type"
    t.jsonb "params"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_notifications_on_company_id"
    t.index ["read_at"], name: "index_notifications_on_read_at"
    t.index ["recipient_type", "recipient_id"], name: "index_notifications_on_recipient"
  end

  create_table "order_discounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.uuid "discount_rule_id"
    t.string "description", null: false
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "menu_promo_id"
    t.uuid "order_item_id"
    t.index ["discount_rule_id"], name: "index_order_discounts_on_discount_rule_id"
    t.index ["menu_promo_id"], name: "index_order_discounts_on_menu_promo_id"
    t.index ["order_id"], name: "index_order_discounts_on_order_id"
    t.index ["order_item_id"], name: "index_order_discounts_on_order_item_id"
  end

  create_table "order_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.string "event_type", null: false
    t.uuid "user_id"
    t.text "description"
    t.datetime "created_at", null: false
    t.index ["order_id"], name: "index_order_events_on_order_id"
    t.index ["user_id"], name: "index_order_events_on_user_id"
  end

  create_table "order_item_modifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_item_id", null: false
    t.uuid "modifier_id", null: false
    t.string "name", null: false
    t.integer "price_adjustment_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["modifier_id"], name: "index_order_item_modifiers_on_modifier_id"
    t.index ["order_item_id"], name: "index_order_item_modifiers_on_order_item_id"
  end

  create_table "order_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.uuid "menu_item_id"
    t.uuid "combo_id"
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["combo_id"], name: "index_order_items_on_combo_id"
    t.index ["menu_item_id"], name: "index_order_items_on_menu_item_id"
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "customer_id"
    t.uuid "user_id", null: false
    t.string "order_number", null: false
    t.string "status", default: "draft", null: false
    t.integer "subtotal_cents"
    t.integer "discount_cents", default: 0, null: false
    t.integer "tax_cents"
    t.integer "tip_cents", default: 0, null: false
    t.integer "total_cents"
    t.text "notes"
    t.string "receipt_sent_via"
    t.string "receipt_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "order_type", default: "pickup", null: false
    t.string "table_number"
    t.text "delivery_address"
    t.uuid "company_id", null: false
    t.uuid "location_id"
    t.uuid "staff_meal_user_id"
    t.uuid "workstation_id"
    t.index ["company_id", "order_number"], name: "index_orders_on_company_id_and_order_number", unique: true
    t.index ["company_id"], name: "index_orders_on_company_id"
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["location_id"], name: "index_orders_on_location_id"
    t.index ["order_type"], name: "index_orders_on_order_type"
    t.index ["receipt_token"], name: "index_orders_on_receipt_token", unique: true
    t.index ["staff_meal_user_id"], name: "index_orders_on_staff_meal_user_id"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["user_id"], name: "index_orders_on_user_id"
    t.index ["workstation_id"], name: "index_orders_on_workstation_id"
  end

  create_table "overtime_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.decimal "daily_threshold_hours", precision: 4, scale: 2
    t.decimal "weekly_threshold_hours", precision: 4, scale: 2, default: "40.0"
    t.decimal "ot_multiplier", precision: 3, scale: 2, default: "1.5"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_overtime_rules_on_company_id"
  end

  create_table "partners", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.integer "account_code", null: false
    t.decimal "ownership_percentage", precision: 5, scale: 2, null: false
    t.boolean "active", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "account_code"], name: "index_partners_on_company_id_and_account_code", unique: true
    t.index ["company_id"], name: "index_partners_on_company_id"
  end

  create_table "payment_method_treasuries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "payment_method", null: false
    t.uuid "treasury_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "payment_method"], name: "idx_on_company_id_payment_method_91108e522b", unique: true
    t.index ["company_id"], name: "index_payment_method_treasuries_on_company_id"
    t.index ["treasury_id"], name: "index_payment_method_treasuries_on_treasury_id"
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.string "payment_method", null: false
    t.integer "amount_cents", null: false
    t.integer "tip_cents", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.string "stripe_payment_intent_id"
    t.string "stripe_charge_id"
    t.integer "refunded_amount_cents", default: 0, null: false
    t.string "refund_reason"
    t.uuid "processed_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.uuid "cash_drawer_session_id"
    t.index ["cash_drawer_session_id"], name: "index_payments_on_cash_drawer_session_id"
    t.index ["company_id"], name: "index_payments_on_company_id"
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["processed_by_user_id"], name: "index_payments_on_processed_by_user_id"
    t.index ["status"], name: "index_payments_on_status"
  end

  create_table "payroll_adjustments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "recorded_by_id", null: false
    t.string "kind", null: false
    t.string "unit_type", null: false
    t.integer "amount_cents", null: false
    t.date "payroll_month", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "overtime_hours", precision: 8, scale: 2
    t.date "happened_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_payroll_adjustments_on_company_id"
    t.index ["payroll_month"], name: "index_payroll_adjustments_on_payroll_month"
    t.index ["recorded_by_id"], name: "index_payroll_adjustments_on_recorded_by_id"
    t.index ["user_id", "payroll_month"], name: "index_payroll_adjustments_on_user_id_and_payroll_month"
    t.index ["user_id"], name: "index_payroll_adjustments_on_user_id"
  end

  create_table "payroll_advances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.uuid "treasury_id", null: false
    t.uuid "paid_by_id", null: false
    t.date "payroll_month", null: false
    t.date "paid_on", null: false
    t.integer "amount_cents", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_payroll_advances_on_company_id"
    t.index ["paid_by_id"], name: "index_payroll_advances_on_paid_by_id"
    t.index ["payroll_month"], name: "index_payroll_advances_on_payroll_month"
    t.index ["treasury_id"], name: "index_payroll_advances_on_treasury_id"
    t.index ["user_id"], name: "index_payroll_advances_on_user_id"
  end

  create_table "payroll_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.uuid "finalized_by_id", null: false
    t.date "payroll_month", null: false
    t.integer "base_salary_cents", default: 0, null: false
    t.integer "daily_rate_cents", default: 0, null: false
    t.integer "penalties_cents", default: 0, null: false
    t.integer "bonuses_cents", default: 0, null: false
    t.integer "net_pay_cents", default: 0, null: false
    t.datetime "finalized_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "advances_cents", default: 0, null: false
    t.integer "remaining_pay_cents", default: 0, null: false
    t.uuid "treasury_id"
    t.date "paid_on"
    t.integer "staff_meals_cents", default: 0, null: false
    t.integer "attendance_pay_cents", default: 0, null: false
    t.decimal "payable_days", precision: 6, scale: 2, default: "0.0", null: false
    t.decimal "bonus_days", precision: 6, scale: 2, default: "0.0", null: false
    t.decimal "penalty_days", precision: 6, scale: 2, default: "0.0", null: false
    t.index ["company_id", "payroll_month"], name: "index_payroll_snapshots_on_company_id_and_payroll_month"
    t.index ["company_id"], name: "index_payroll_snapshots_on_company_id"
    t.index ["finalized_by_id"], name: "index_payroll_snapshots_on_finalized_by_id"
    t.index ["treasury_id"], name: "index_payroll_snapshots_on_treasury_id"
    t.index ["user_id", "payroll_month"], name: "index_payroll_snapshots_on_user_id_and_payroll_month", unique: true
    t.index ["user_id"], name: "index_payroll_snapshots_on_user_id"
  end

  create_table "print_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.uuid "printer_id"
    t.string "print_type", default: "receipt", null: false
    t.string "status", null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_print_logs_on_order_id"
    t.index ["print_type"], name: "index_print_logs_on_print_type"
    t.index ["printer_id"], name: "index_print_logs_on_printer_id"
    t.index ["status"], name: "index_print_logs_on_status"
  end

  create_table "printer_menu_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "printer_id", null: false
    t.uuid "menu_item_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id"], name: "index_printer_menu_items_on_menu_item_id"
    t.index ["printer_id", "menu_item_id"], name: "index_printer_menu_items_on_printer_id_and_menu_item_id", unique: true
    t.index ["printer_id"], name: "index_printer_menu_items_on_printer_id"
  end

  create_table "printers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "printer_type", default: "receipt", null: false
    t.string "connection_type", default: "network", null: false
    t.string "host"
    t.integer "port", default: 9100
    t.string "station"
    t.string "paper_width", default: "80mm"
    t.boolean "active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.uuid "location_id"
    t.index ["active"], name: "index_printers_on_active"
    t.index ["company_id"], name: "index_printers_on_company_id"
    t.index ["location_id"], name: "index_printers_on_location_id"
    t.index ["name"], name: "index_printers_on_name"
    t.index ["printer_type", "is_default"], name: "index_printers_on_printer_type_and_is_default"
  end

  create_table "receipt_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.string "delivery_method", null: false
    t.string "recipient", null: false
    t.string "status", null: false
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_receipt_logs_on_order_id"
  end

  create_table "recipes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "menu_item_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "quantity_used", precision: 10, scale: 4, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "unit_id"
    t.index ["ingredient_id"], name: "index_recipes_on_ingredient_id"
    t.index ["menu_item_id", "ingredient_id"], name: "index_recipes_on_menu_item_id_and_ingredient_id", unique: true
    t.index ["menu_item_id"], name: "index_recipes_on_menu_item_id"
    t.index ["unit_id"], name: "index_recipes_on_unit_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "key"
    t.string "name", null: false
    t.jsonb "permissions", default: [], null: false
    t.boolean "built_in", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "key"], name: "index_roles_on_company_id_and_key", unique: true, where: "(key IS NOT NULL)"
    t.index ["company_id"], name: "index_roles_on_company_id"
  end

  create_table "shift_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.datetime "clocked_in_at", null: false
    t.datetime "clocked_out_at"
    t.integer "break_minutes", default: 0, null: false
    t.integer "hourly_rate_cents", null: false
    t.integer "tips_cents", default: 0, null: false
    t.string "status", default: "active", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["clocked_in_at"], name: "index_shift_logs_on_clocked_in_at"
    t.index ["company_id"], name: "index_shift_logs_on_company_id"
    t.index ["status"], name: "index_shift_logs_on_status"
    t.index ["user_id"], name: "index_shift_logs_on_user_id"
  end

  create_table "staff_attendances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.uuid "attendance_status_id", null: false
    t.uuid "recorded_by_id"
    t.date "date", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attendance_status_id"], name: "index_staff_attendances_on_attendance_status_id"
    t.index ["company_id", "date"], name: "index_staff_attendances_on_company_id_and_date"
    t.index ["company_id"], name: "index_staff_attendances_on_company_id"
    t.index ["recorded_by_id"], name: "index_staff_attendances_on_recorded_by_id"
    t.index ["user_id", "date"], name: "index_staff_attendances_on_user_id_and_date", unique: true
    t.index ["user_id"], name: "index_staff_attendances_on_user_id"
  end

  create_table "stock_adjustments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ingredient_id", null: false
    t.uuid "user_id", null: false
    t.uuid "stock_batch_id"
    t.decimal "quantity_delta", precision: 10, scale: 3, null: false
    t.string "adjustment_type", null: false
    t.string "reason_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "location_id"
    t.uuid "stock_transfer_id"
    t.uuid "unit_id"
    t.index ["adjustment_type"], name: "index_stock_adjustments_on_adjustment_type"
    t.index ["created_at"], name: "index_stock_adjustments_on_created_at"
    t.index ["ingredient_id"], name: "index_stock_adjustments_on_ingredient_id"
    t.index ["location_id"], name: "index_stock_adjustments_on_location_id"
    t.index ["stock_batch_id"], name: "index_stock_adjustments_on_stock_batch_id"
    t.index ["stock_transfer_id"], name: "index_stock_adjustments_on_stock_transfer_id"
    t.index ["unit_id"], name: "index_stock_adjustments_on_unit_id"
    t.index ["user_id"], name: "index_stock_adjustments_on_user_id"
  end

  create_table "stock_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ingredient_id", null: false
    t.uuid "supplier_id"
    t.decimal "quantity_received", precision: 10, scale: 3, null: false
    t.decimal "quantity_remaining", precision: 10, scale: 3, null: false
    t.integer "cost_per_unit_cents", default: 0, null: false
    t.date "received_on", null: false
    t.date "expires_on"
    t.string "batch_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "vendor_invoice_line_id"
    t.uuid "location_id"
    t.index ["expires_on"], name: "index_stock_batches_on_expires_on"
    t.index ["ingredient_id"], name: "index_stock_batches_on_ingredient_id"
    t.index ["location_id"], name: "index_stock_batches_on_location_id"
    t.index ["received_on"], name: "index_stock_batches_on_received_on"
    t.index ["supplier_id"], name: "index_stock_batches_on_supplier_id"
    t.index ["vendor_invoice_line_id"], name: "index_stock_batches_on_vendor_invoice_line_id"
  end

  create_table "stock_take_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "stock_take_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "expected_quantity", precision: 10, scale: 3
    t.decimal "counted_quantity", precision: 10, scale: 3
    t.decimal "variance", precision: 10, scale: 3
    t.boolean "adjusted", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "counted_unit_id"
    t.index ["counted_unit_id"], name: "index_stock_take_items_on_counted_unit_id"
    t.index ["ingredient_id"], name: "index_stock_take_items_on_ingredient_id"
    t.index ["stock_take_id"], name: "index_stock_take_items_on_stock_take_id"
  end

  create_table "stock_takes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "status", default: "in_progress", null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.uuid "location_id"
    t.uuid "supplier_id"
    t.index ["company_id"], name: "index_stock_takes_on_company_id"
    t.index ["location_id"], name: "index_stock_takes_on_location_id"
    t.index ["supplier_id"], name: "index_stock_takes_on_supplier_id"
    t.index ["user_id"], name: "index_stock_takes_on_user_id"
  end

  create_table "stock_transfer_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "stock_transfer_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "quantity_requested", precision: 10, scale: 3, default: "0.0", null: false
    t.decimal "quantity_sent", precision: 10, scale: 3, default: "0.0"
    t.decimal "quantity_received", precision: 10, scale: 3, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "unit_id"
    t.integer "position", default: 0, null: false
    t.index ["ingredient_id"], name: "index_stock_transfer_lines_on_ingredient_id"
    t.index ["stock_transfer_id", "ingredient_id"], name: "idx_on_stock_transfer_id_ingredient_id_597e5cba74", unique: true
    t.index ["stock_transfer_id"], name: "index_stock_transfer_lines_on_stock_transfer_id"
    t.index ["unit_id"], name: "index_stock_transfer_lines_on_unit_id"
  end

  create_table "stock_transfer_shipment_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "stock_transfer_shipment_id", null: false
    t.uuid "stock_transfer_line_id", null: false
    t.decimal "quantity_sent", precision: 10, scale: 3, default: "0.0", null: false
    t.decimal "quantity_received", precision: 10, scale: 3
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["stock_transfer_line_id"], name: "index_stock_transfer_shipment_lines_on_stock_transfer_line_id"
    t.index ["stock_transfer_shipment_id", "stock_transfer_line_id"], name: "index_shipment_lines_on_shipment_and_transfer_line", unique: true
    t.index ["stock_transfer_shipment_id"], name: "idx_on_stock_transfer_shipment_id_5df1410351"
  end

  create_table "stock_transfer_shipments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "stock_transfer_id", null: false
    t.integer "sequence", default: 1, null: false
    t.string "status", default: "in_transit", null: false
    t.uuid "sent_by_id", null: false
    t.uuid "received_by_id"
    t.datetime "sent_at", null: false
    t.datetime "received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["received_by_id"], name: "index_stock_transfer_shipments_on_received_by_id"
    t.index ["sent_by_id"], name: "index_stock_transfer_shipments_on_sent_by_id"
    t.index ["stock_transfer_id", "sequence"], name: "idx_on_stock_transfer_id_sequence_1bc36b196f", unique: true
    t.index ["stock_transfer_id"], name: "index_stock_transfer_shipments_on_stock_transfer_id"
  end

  create_table "stock_transfer_template_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "stock_transfer_template_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "default_quantity", precision: 10, scale: 3, default: "0.0", null: false
    t.uuid "unit_id"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_stock_transfer_template_lines_on_ingredient_id"
    t.index ["stock_transfer_template_id", "ingredient_id"], name: "index_st_template_lines_on_template_and_ingredient", unique: true
    t.index ["stock_transfer_template_id"], name: "index_st_template_lines_on_template_id"
    t.index ["unit_id"], name: "index_stock_transfer_template_lines_on_unit_id"
  end

  create_table "stock_transfer_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.text "notes"
    t.uuid "default_from_location_id"
    t.uuid "default_to_location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "active"], name: "index_stock_transfer_templates_on_company_id_and_active"
    t.index ["company_id", "name"], name: "index_stock_transfer_templates_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_stock_transfer_templates_on_company_id"
    t.index ["default_from_location_id"], name: "index_stock_transfer_templates_on_default_from_location_id"
    t.index ["default_to_location_id"], name: "index_stock_transfer_templates_on_default_to_location_id"
  end

  create_table "stock_transfers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "from_location_id", null: false
    t.uuid "to_location_id", null: false
    t.uuid "requested_by_id", null: false
    t.uuid "sent_by_id"
    t.uuid "received_by_id"
    t.string "transfer_number", null: false
    t.string "status", default: "requested", null: false
    t.text "notes"
    t.datetime "requested_at", null: false
    t.datetime "sent_at"
    t.datetime "received_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "transfer_number"], name: "index_stock_transfers_on_company_id_and_transfer_number", unique: true
    t.index ["company_id"], name: "index_stock_transfers_on_company_id"
    t.index ["from_location_id"], name: "index_stock_transfers_on_from_location_id"
    t.index ["received_by_id"], name: "index_stock_transfers_on_received_by_id"
    t.index ["requested_by_id"], name: "index_stock_transfers_on_requested_by_id"
    t.index ["sent_by_id"], name: "index_stock_transfers_on_sent_by_id"
    t.index ["status"], name: "index_stock_transfers_on_status"
    t.index ["to_location_id"], name: "index_stock_transfers_on_to_location_id"
  end

  create_table "super_admin_users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_super_admin_users_on_email", unique: true
  end

  create_table "supplier_ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "supplier_id", null: false
    t.uuid "ingredient_id", null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "preferred", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "vendor_product_name"
    t.string "vendor_sku"
    t.index ["ingredient_id"], name: "index_supplier_ingredients_on_ingredient_id"
    t.index ["supplier_id", "ingredient_id"], name: "index_supplier_ingredients_on_supplier_id_and_ingredient_id", unique: true
    t.index ["supplier_id"], name: "index_supplier_ingredients_on_supplier_id"
  end

  create_table "supplier_price_histories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "supplier_id", null: false
    t.uuid "ingredient_id", null: false
    t.integer "price_cents", null: false
    t.date "effective_date", null: false
    t.uuid "recorded_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_supplier_price_histories_on_ingredient_id"
    t.index ["recorded_by_user_id"], name: "index_supplier_price_histories_on_recorded_by_user_id"
    t.index ["supplier_id", "ingredient_id", "effective_date"], name: "index_supplier_price_histories_on_supplier_ingredient_date"
    t.index ["supplier_id"], name: "index_supplier_price_histories_on_supplier_id"
  end

  create_table "suppliers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "contact_name"
    t.string "email"
    t.string "phone"
    t.text "address"
    t.integer "lead_time_days", default: 1
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.uuid "treasury_id"
    t.index ["company_id"], name: "index_suppliers_on_company_id"
    t.index ["name"], name: "index_suppliers_on_name"
    t.index ["treasury_id"], name: "index_suppliers_on_treasury_id"
  end

  create_table "tax_rates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.decimal "rate", precision: 5, scale: 4, null: false
    t.string "tax_category", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["active"], name: "index_tax_rates_on_active"
    t.index ["company_id"], name: "index_tax_rates_on_company_id"
    t.index ["tax_category"], name: "index_tax_rates_on_tax_category"
  end

  create_table "treasuries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "treasury_type", null: false
    t.integer "balance_cents", default: 0, null: false
    t.integer "opening_balance_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.integer "position", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.uuid "supplier_id"
    t.boolean "restricted", default: false, null: false
    t.index ["active"], name: "index_treasuries_on_active"
    t.index ["company_id", "name"], name: "index_treasuries_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_treasuries_on_company_id"
    t.index ["supplier_id"], name: "index_treasuries_on_supplier_id"
  end

  create_table "treasury_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "treasury_id", null: false
    t.uuid "user_id", null: false
    t.integer "amount_cents", null: false
    t.string "kind", null: false
    t.string "description", null: false
    t.date "occurred_on", null: false
    t.string "source_record_type"
    t.uuid "source_record_id"
    t.integer "balance_after_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_treasury_transactions_on_company_id"
    t.index ["kind"], name: "index_treasury_transactions_on_kind"
    t.index ["occurred_on"], name: "index_treasury_transactions_on_occurred_on"
    t.index ["source_record_type", "source_record_id"], name: "index_treasury_transactions_on_source"
    t.index ["treasury_id"], name: "index_treasury_transactions_on_treasury_id"
    t.index ["user_id"], name: "index_treasury_transactions_on_user_id"
  end

  create_table "treasury_transfers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "from_treasury_id", null: false
    t.uuid "to_treasury_id", null: false
    t.uuid "user_id", null: false
    t.integer "amount_cents", null: false
    t.string "description", null: false
    t.date "occurred_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "company_id", null: false
    t.index ["company_id"], name: "index_treasury_transfers_on_company_id"
    t.index ["from_treasury_id"], name: "index_treasury_transfers_on_from_treasury_id"
    t.index ["occurred_on"], name: "index_treasury_transfers_on_occurred_on"
    t.index ["to_treasury_id"], name: "index_treasury_transfers_on_to_treasury_id"
    t.index ["user_id"], name: "index_treasury_transfers_on_user_id"
  end

  create_table "units", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.boolean "system", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_units_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_units_on_company_id"
  end

  create_table "user_locations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "location_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_user_locations_on_location_id"
    t.index ["user_id", "location_id"], name: "index_user_locations_on_user_id_and_location_id", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "role", default: "cashier", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "hourly_rate_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.string "pin_digest"
    t.integer "monthly_salary_cents", default: 0, null: false
    t.string "payroll_access_token", null: false
    t.uuid "company_id", null: false
    t.uuid "role_id"
    t.boolean "all_locations", default: true, null: false
    t.uuid "assigned_treasury_id"
    t.index ["active"], name: "index_users_on_active"
    t.index ["assigned_treasury_id"], name: "index_users_on_assigned_treasury_id"
    t.index ["company_id", "email"], name: "index_users_on_company_id_and_email", unique: true
    t.index ["company_id"], name: "index_users_on_company_id"
    t.index ["payroll_access_token"], name: "index_users_on_payroll_access_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role_id"], name: "index_users_on_role_id"
  end

  create_table "vendor_invoice_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "vendor_invoice_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "quantity", precision: 10, scale: 3, null: false
    t.integer "unit_price_cents", null: false
    t.date "expires_on"
    t.string "batch_reference"
    t.text "line_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "line_total_cents", default: 0, null: false
    t.uuid "unit_id"
    t.integer "position", default: 0, null: false
    t.index ["ingredient_id"], name: "index_vendor_invoice_lines_on_ingredient_id"
    t.index ["unit_id"], name: "index_vendor_invoice_lines_on_unit_id"
    t.index ["vendor_invoice_id"], name: "index_vendor_invoice_lines_on_vendor_invoice_id"
  end

  create_table "vendor_invoice_payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "vendor_invoice_id", null: false
    t.uuid "user_id", null: false
    t.uuid "treasury_id", null: false
    t.integer "amount_cents", null: false
    t.date "payment_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_vendor_invoice_payments_on_company_id"
    t.index ["payment_date"], name: "index_vendor_invoice_payments_on_payment_date"
    t.index ["treasury_id"], name: "index_vendor_invoice_payments_on_treasury_id"
    t.index ["user_id"], name: "index_vendor_invoice_payments_on_user_id"
    t.index ["vendor_invoice_id"], name: "index_vendor_invoice_payments_on_vendor_invoice_id"
  end

  create_table "vendor_invoices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "supplier_id", null: false
    t.uuid "user_id", null: false
    t.string "invoice_number", null: false
    t.date "invoice_date", null: false
    t.date "received_on", null: false
    t.string "payment_status", default: "unpaid", null: false
    t.integer "total_cents", default: 0, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "amount_paid_cents", default: 0, null: false
    t.uuid "location_id"
    t.string "discount_type"
    t.decimal "discount_value", precision: 10, scale: 2
    t.text "discount_notes"
    t.index ["company_id", "supplier_id", "invoice_number"], name: "index_vendor_invoices_on_company_supplier_and_number", unique: true
    t.index ["company_id"], name: "index_vendor_invoices_on_company_id"
    t.index ["invoice_date"], name: "index_vendor_invoices_on_invoice_date"
    t.index ["location_id"], name: "index_vendor_invoices_on_location_id"
    t.index ["payment_status"], name: "index_vendor_invoices_on_payment_status"
    t.index ["supplier_id"], name: "index_vendor_invoices_on_supplier_id"
    t.index ["user_id"], name: "index_vendor_invoices_on_user_id"
  end

  create_table "workstations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "location_id", null: false
    t.string "name", null: false
    t.boolean "active", default: true, null: false
    t.uuid "receipt_printer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "active"], name: "index_workstations_on_company_id_and_active"
    t.index ["company_id"], name: "index_workstations_on_company_id"
    t.index ["location_id", "name"], name: "index_workstations_on_location_id_and_name", unique: true
    t.index ["location_id"], name: "index_workstations_on_location_id"
    t.index ["receipt_printer_id"], name: "index_workstations_on_receipt_printer_id"
  end

  add_foreign_key "accounting_integrations", "companies"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "attendance_statuses", "companies"
  add_foreign_key "audit_log_entries", "companies"
  add_foreign_key "audit_log_entries", "users"
  add_foreign_key "budgets", "companies"
  add_foreign_key "budgets", "expense_categories"
  add_foreign_key "cash_drawer_sessions", "companies"
  add_foreign_key "cash_drawer_sessions", "locations"
  add_foreign_key "cash_drawer_sessions", "treasuries"
  add_foreign_key "cash_drawer_sessions", "users"
  add_foreign_key "categories", "companies"
  add_foreign_key "combo_items", "combos"
  add_foreign_key "combo_items", "menu_items"
  add_foreign_key "combos", "companies"
  add_foreign_key "company_settings", "companies"
  add_foreign_key "customer_addresses", "customers"
  add_foreign_key "customers", "companies"
  add_foreign_key "digital_wallet_day_closes", "companies"
  add_foreign_key "digital_wallet_day_closes", "locations"
  add_foreign_key "digital_wallet_day_closes", "users", column: "recorded_by_id"
  add_foreign_key "discount_rules", "companies"
  add_foreign_key "expense_categories", "companies"
  add_foreign_key "expenses", "companies"
  add_foreign_key "expenses", "expense_categories"
  add_foreign_key "expenses", "treasuries"
  add_foreign_key "expenses", "users"
  add_foreign_key "fixed_assets", "companies"
  add_foreign_key "fixed_assets", "locations"
  add_foreign_key "fixed_assets", "users", column: "recorded_by_id"
  add_foreign_key "gift_cards", "companies"
  add_foreign_key "income_categories", "companies"
  add_foreign_key "incomes", "companies"
  add_foreign_key "incomes", "income_categories"
  add_foreign_key "incomes", "treasuries"
  add_foreign_key "incomes", "users"
  add_foreign_key "ingredient_categories", "companies"
  add_foreign_key "ingredient_locations", "ingredients"
  add_foreign_key "ingredient_locations", "locations"
  add_foreign_key "ingredient_units", "companies"
  add_foreign_key "ingredient_units", "ingredients"
  add_foreign_key "ingredient_units", "units"
  add_foreign_key "ingredients", "companies"
  add_foreign_key "ingredients", "ingredient_categories"
  add_foreign_key "ingredients", "units"
  add_foreign_key "journal_entries", "companies"
  add_foreign_key "journal_entries", "journal_entries", column: "reversal_of_id"
  add_foreign_key "journal_entries", "users", column: "created_by_id"
  add_foreign_key "journal_entry_lines", "journal_entries"
  add_foreign_key "journal_entry_lines", "treasuries"
  add_foreign_key "loans", "companies"
  add_foreign_key "location_menu_items", "locations"
  add_foreign_key "location_menu_items", "menu_items"
  add_foreign_key "location_operating_days", "companies"
  add_foreign_key "location_operating_days", "locations"
  add_foreign_key "location_operating_days", "users", column: "closed_by_id"
  add_foreign_key "location_operating_days", "users", column: "opened_by_id"
  add_foreign_key "locations", "companies"
  add_foreign_key "loyalty_transactions", "customers"
  add_foreign_key "loyalty_transactions", "orders"
  add_foreign_key "manufacturing_runs", "companies"
  add_foreign_key "manufacturing_runs", "locations"
  add_foreign_key "manufacturing_runs", "manufacturing_templates"
  add_foreign_key "manufacturing_runs", "units", column: "main_input_unit_id"
  add_foreign_key "manufacturing_runs", "users"
  add_foreign_key "manufacturing_runs", "users", column: "reversed_by_id"
  add_foreign_key "manufacturing_template_lines", "ingredients"
  add_foreign_key "manufacturing_template_lines", "manufacturing_templates"
  add_foreign_key "manufacturing_template_lines", "units"
  add_foreign_key "manufacturing_templates", "companies"
  add_foreign_key "manufacturing_templates", "ingredients", column: "main_ingredient_id"
  add_foreign_key "manufacturing_templates", "ingredients", column: "output_ingredient_id"
  add_foreign_key "manufacturing_templates", "units", column: "yield_unit_id"
  add_foreign_key "menu_item_modifier_groups", "menu_items"
  add_foreign_key "menu_item_modifier_groups", "modifier_groups"
  add_foreign_key "menu_items", "categories"
  add_foreign_key "menu_items", "companies"
  add_foreign_key "menu_promos", "companies"
  add_foreign_key "menu_promos", "locations"
  add_foreign_key "menu_promos", "menu_items"
  add_foreign_key "modifier_groups", "companies"
  add_foreign_key "modifier_recipes", "ingredients"
  add_foreign_key "modifier_recipes", "modifiers"
  add_foreign_key "modifiers", "companies"
  add_foreign_key "modifiers", "modifier_groups"
  add_foreign_key "notifications", "companies"
  add_foreign_key "order_discounts", "discount_rules"
  add_foreign_key "order_discounts", "menu_promos"
  add_foreign_key "order_discounts", "order_items"
  add_foreign_key "order_discounts", "orders"
  add_foreign_key "order_events", "orders"
  add_foreign_key "order_events", "users"
  add_foreign_key "order_item_modifiers", "modifiers"
  add_foreign_key "order_item_modifiers", "order_items"
  add_foreign_key "order_items", "combos"
  add_foreign_key "order_items", "menu_items"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "companies"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "locations"
  add_foreign_key "orders", "users"
  add_foreign_key "orders", "users", column: "staff_meal_user_id"
  add_foreign_key "orders", "workstations"
  add_foreign_key "overtime_rules", "companies"
  add_foreign_key "partners", "companies"
  add_foreign_key "payment_method_treasuries", "companies"
  add_foreign_key "payment_method_treasuries", "treasuries"
  add_foreign_key "payments", "cash_drawer_sessions"
  add_foreign_key "payments", "companies"
  add_foreign_key "payments", "orders"
  add_foreign_key "payments", "users", column: "processed_by_user_id"
  add_foreign_key "payroll_adjustments", "companies"
  add_foreign_key "payroll_adjustments", "users"
  add_foreign_key "payroll_adjustments", "users", column: "recorded_by_id"
  add_foreign_key "payroll_advances", "companies"
  add_foreign_key "payroll_advances", "treasuries"
  add_foreign_key "payroll_advances", "users"
  add_foreign_key "payroll_advances", "users", column: "paid_by_id"
  add_foreign_key "payroll_snapshots", "companies"
  add_foreign_key "payroll_snapshots", "treasuries"
  add_foreign_key "payroll_snapshots", "users"
  add_foreign_key "payroll_snapshots", "users", column: "finalized_by_id"
  add_foreign_key "print_logs", "orders"
  add_foreign_key "print_logs", "printers"
  add_foreign_key "printer_menu_items", "menu_items"
  add_foreign_key "printer_menu_items", "printers"
  add_foreign_key "printers", "companies"
  add_foreign_key "printers", "locations"
  add_foreign_key "receipt_logs", "orders"
  add_foreign_key "recipes", "ingredients"
  add_foreign_key "recipes", "menu_items"
  add_foreign_key "recipes", "units"
  add_foreign_key "shift_logs", "companies"
  add_foreign_key "shift_logs", "users"
  add_foreign_key "staff_attendances", "attendance_statuses"
  add_foreign_key "staff_attendances", "companies"
  add_foreign_key "staff_attendances", "users"
  add_foreign_key "staff_attendances", "users", column: "recorded_by_id"
  add_foreign_key "stock_adjustments", "ingredients"
  add_foreign_key "stock_adjustments", "locations"
  add_foreign_key "stock_adjustments", "stock_batches"
  add_foreign_key "stock_adjustments", "stock_transfers"
  add_foreign_key "stock_adjustments", "units"
  add_foreign_key "stock_adjustments", "users"
  add_foreign_key "stock_batches", "ingredients"
  add_foreign_key "stock_batches", "locations"
  add_foreign_key "stock_batches", "suppliers"
  add_foreign_key "stock_batches", "vendor_invoice_lines"
  add_foreign_key "stock_take_items", "ingredients"
  add_foreign_key "stock_take_items", "stock_takes"
  add_foreign_key "stock_take_items", "units", column: "counted_unit_id"
  add_foreign_key "stock_takes", "companies"
  add_foreign_key "stock_takes", "locations"
  add_foreign_key "stock_takes", "suppliers"
  add_foreign_key "stock_takes", "users"
  add_foreign_key "stock_transfer_lines", "ingredients"
  add_foreign_key "stock_transfer_lines", "stock_transfers"
  add_foreign_key "stock_transfer_lines", "units"
  add_foreign_key "stock_transfer_shipment_lines", "stock_transfer_lines"
  add_foreign_key "stock_transfer_shipment_lines", "stock_transfer_shipments"
  add_foreign_key "stock_transfer_shipments", "stock_transfers"
  add_foreign_key "stock_transfer_shipments", "users", column: "received_by_id"
  add_foreign_key "stock_transfer_shipments", "users", column: "sent_by_id"
  add_foreign_key "stock_transfer_template_lines", "ingredients"
  add_foreign_key "stock_transfer_template_lines", "stock_transfer_templates"
  add_foreign_key "stock_transfer_template_lines", "units"
  add_foreign_key "stock_transfer_templates", "companies"
  add_foreign_key "stock_transfer_templates", "locations", column: "default_from_location_id"
  add_foreign_key "stock_transfer_templates", "locations", column: "default_to_location_id"
  add_foreign_key "stock_transfers", "companies"
  add_foreign_key "stock_transfers", "locations", column: "from_location_id"
  add_foreign_key "stock_transfers", "locations", column: "to_location_id"
  add_foreign_key "stock_transfers", "users", column: "received_by_id"
  add_foreign_key "stock_transfers", "users", column: "requested_by_id"
  add_foreign_key "stock_transfers", "users", column: "sent_by_id"
  add_foreign_key "supplier_ingredients", "ingredients"
  add_foreign_key "supplier_ingredients", "suppliers"
  add_foreign_key "supplier_price_histories", "ingredients"
  add_foreign_key "supplier_price_histories", "suppliers"
  add_foreign_key "supplier_price_histories", "users", column: "recorded_by_user_id"
  add_foreign_key "suppliers", "companies"
  add_foreign_key "suppliers", "treasuries"
  add_foreign_key "tax_rates", "companies"
  add_foreign_key "treasuries", "companies"
  add_foreign_key "treasury_transactions", "companies"
  add_foreign_key "treasury_transactions", "treasuries"
  add_foreign_key "treasury_transactions", "users"
  add_foreign_key "treasury_transfers", "companies"
  add_foreign_key "treasury_transfers", "treasuries", column: "from_treasury_id"
  add_foreign_key "treasury_transfers", "treasuries", column: "to_treasury_id"
  add_foreign_key "treasury_transfers", "users"
  add_foreign_key "units", "companies"
  add_foreign_key "user_locations", "locations"
  add_foreign_key "user_locations", "users"
  add_foreign_key "users", "companies"
  add_foreign_key "users", "roles"
  add_foreign_key "users", "treasuries", column: "assigned_treasury_id", on_delete: :nullify
  add_foreign_key "vendor_invoice_lines", "ingredients"
  add_foreign_key "vendor_invoice_lines", "units"
  add_foreign_key "vendor_invoice_lines", "vendor_invoices"
  add_foreign_key "vendor_invoice_payments", "companies"
  add_foreign_key "vendor_invoice_payments", "treasuries"
  add_foreign_key "vendor_invoice_payments", "users"
  add_foreign_key "vendor_invoice_payments", "vendor_invoices"
  add_foreign_key "vendor_invoices", "companies"
  add_foreign_key "vendor_invoices", "locations"
  add_foreign_key "vendor_invoices", "suppliers"
  add_foreign_key "vendor_invoices", "users"
  add_foreign_key "workstations", "companies"
  add_foreign_key "workstations", "locations"
  add_foreign_key "workstations", "printers", column: "receipt_printer_id"
end
