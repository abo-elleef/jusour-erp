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

ActiveRecord::Schema[7.1].define(version: 2026_06_08_000000) do
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
    t.index ["provider"], name: "index_accounting_integrations_on_provider", unique: true
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

  create_table "audit_log_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "action", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.jsonb "changes_snapshot", default: {}, null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_log_entries_on_action"
    t.index ["created_at"], name: "index_audit_log_entries_on_created_at"
    t.index ["record_type", "record_id"], name: "index_audit_log_entries_on_record_type_and_record_id"
    t.index ["user_id"], name: "index_audit_log_entries_on_user_id"
  end

  create_table "budgets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "expense_category_id", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expense_category_id", "year", "month"], name: "index_budgets_on_expense_category_id_and_year_and_month", unique: true
    t.index ["expense_category_id"], name: "index_budgets_on_expense_category_id"
  end

  create_table "cash_drawer_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.date "session_date", null: false
    t.string "shift", null: false
    t.integer "opening_float_cents", default: 0, null: false
    t.integer "expected_cash_cents"
    t.integer "counted_cash_cents"
    t.integer "variance_cents"
    t.string "status", default: "open", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "session_date", "shift"], name: "idx_on_user_id_session_date_shift_04dd8c9892", unique: true
    t.index ["user_id"], name: "index_cash_drawer_sessions_on_user_id"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.integer "position"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
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
    t.index ["email"], name: "index_customers_on_email", unique: true
    t.index ["phone"], name: "index_customers_on_phone", unique: true
    t.index ["phone_secondary"], name: "index_customers_on_phone_secondary", unique: true, where: "(phone_secondary IS NOT NULL)"
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
    t.index ["active"], name: "index_discount_rules_on_active"
    t.index ["code"], name: "index_discount_rules_on_code", unique: true
  end

  create_table "expense_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "category_type", null: false
    t.boolean "system_managed", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_expense_categories_on_name", unique: true
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
    t.index ["expense_category_id"], name: "index_expenses_on_expense_category_id"
    t.index ["expense_date"], name: "index_expenses_on_expense_date"
    t.index ["is_auto_generated"], name: "index_expenses_on_is_auto_generated"
    t.index ["source_record_type", "source_record_id"], name: "index_expenses_on_source_record_type_and_source_record_id"
    t.index ["user_id"], name: "index_expenses_on_user_id"
  end

  create_table "gift_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", null: false
    t.integer "balance_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_gift_cards_on_code", unique: true
  end

  create_table "ingredient_categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.integer "position", default: 0
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_ingredient_categories_on_name", unique: true
  end

  create_table "ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ingredient_category_id", null: false
    t.string "name", null: false
    t.string "unit", null: false
    t.decimal "reorder_threshold", precision: 10, scale: 3, default: "0.0", null: false
    t.decimal "quantity_on_hand", precision: 10, scale: 3, default: "0.0", null: false
    t.integer "cost_per_unit_cents", default: 0, null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_ingredients_on_active"
    t.index ["ingredient_category_id"], name: "index_ingredients_on_ingredient_category_id"
    t.index ["name"], name: "index_ingredients_on_name"
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
    t.index ["available"], name: "index_menu_items_on_available"
    t.index ["category_id"], name: "index_menu_items_on_category_id"
  end

  create_table "modifier_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.boolean "required", default: false, null: false
    t.boolean "multi_select", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "modifiers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "modifier_group_id", null: false
    t.string "name", null: false
    t.integer "price_adjustment_cents", default: 0, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["discount_rule_id"], name: "index_order_discounts_on_discount_rule_id"
    t.index ["order_id"], name: "index_order_discounts_on_order_id"
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
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["order_type"], name: "index_orders_on_order_type"
    t.index ["receipt_token"], name: "index_orders_on_receipt_token", unique: true
    t.index ["status"], name: "index_orders_on_status"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "overtime_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.decimal "daily_threshold_hours", precision: 4, scale: 2
    t.decimal "weekly_threshold_hours", precision: 4, scale: 2, default: "40.0"
    t.decimal "ot_multiplier", precision: 3, scale: 2, default: "1.5"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["order_id"], name: "index_payments_on_order_id"
    t.index ["processed_by_user_id"], name: "index_payments_on_processed_by_user_id"
    t.index ["status"], name: "index_payments_on_status"
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

  create_table "printers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "printer_type", default: "receipt", null: false
    t.string "connection_type", default: "network", null: false
    t.string "host"
    t.integer "port", default: 9100
    t.string "location"
    t.string "paper_width", default: "80mm"
    t.boolean "active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_printers_on_active"
    t.index ["name"], name: "index_printers_on_name"
    t.index ["printer_type", "is_default"], name: "index_printers_on_printer_type_and_is_default"
  end

  create_table "purchase_order_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "purchase_order_id", null: false
    t.uuid "ingredient_id", null: false
    t.decimal "quantity_ordered", precision: 10, scale: 3, null: false
    t.decimal "quantity_received", precision: 10, scale: 3, default: "0.0"
    t.integer "unit_price_cents", null: false
    t.string "status", default: "pending"
    t.text "discrepancy_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ingredient_id"], name: "index_purchase_order_items_on_ingredient_id"
    t.index ["purchase_order_id"], name: "index_purchase_order_items_on_purchase_order_id"
  end

  create_table "purchase_orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "supplier_id", null: false
    t.uuid "user_id", null: false
    t.string "po_number", null: false
    t.string "status", default: "draft", null: false
    t.date "ordered_on"
    t.date "expected_on"
    t.integer "total_cents", default: 0
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ordered_on"], name: "index_purchase_orders_on_ordered_on"
    t.index ["po_number"], name: "index_purchase_orders_on_po_number", unique: true
    t.index ["status"], name: "index_purchase_orders_on_status"
    t.index ["supplier_id"], name: "index_purchase_orders_on_supplier_id"
    t.index ["user_id"], name: "index_purchase_orders_on_user_id"
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
    t.index ["ingredient_id"], name: "index_recipes_on_ingredient_id"
    t.index ["menu_item_id", "ingredient_id"], name: "index_recipes_on_menu_item_id_and_ingredient_id", unique: true
    t.index ["menu_item_id"], name: "index_recipes_on_menu_item_id"
  end

  create_table "settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
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
    t.index ["clocked_in_at"], name: "index_shift_logs_on_clocked_in_at"
    t.index ["status"], name: "index_shift_logs_on_status"
    t.index ["user_id"], name: "index_shift_logs_on_user_id"
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
    t.index ["adjustment_type"], name: "index_stock_adjustments_on_adjustment_type"
    t.index ["created_at"], name: "index_stock_adjustments_on_created_at"
    t.index ["ingredient_id"], name: "index_stock_adjustments_on_ingredient_id"
    t.index ["stock_batch_id"], name: "index_stock_adjustments_on_stock_batch_id"
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
    t.index ["expires_on"], name: "index_stock_batches_on_expires_on"
    t.index ["ingredient_id"], name: "index_stock_batches_on_ingredient_id"
    t.index ["received_on"], name: "index_stock_batches_on_received_on"
    t.index ["supplier_id"], name: "index_stock_batches_on_supplier_id"
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
    t.index ["user_id"], name: "index_stock_takes_on_user_id"
  end

  create_table "supplier_ingredients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "supplier_id", null: false
    t.uuid "ingredient_id", null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "preferred", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["name"], name: "index_suppliers_on_name"
  end

  create_table "tax_rates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.decimal "rate", precision: 5, scale: 4, null: false
    t.string "tax_category", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_tax_rates_on_active"
    t.index ["tax_category"], name: "index_tax_rates_on_tax_category"
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
    t.index ["active"], name: "index_users_on_active"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_log_entries", "users"
  add_foreign_key "budgets", "expense_categories"
  add_foreign_key "cash_drawer_sessions", "users"
  add_foreign_key "combo_items", "combos"
  add_foreign_key "combo_items", "menu_items"
  add_foreign_key "customer_addresses", "customers"
  add_foreign_key "expenses", "expense_categories"
  add_foreign_key "expenses", "users"
  add_foreign_key "ingredients", "ingredient_categories"
  add_foreign_key "loyalty_transactions", "customers"
  add_foreign_key "loyalty_transactions", "orders"
  add_foreign_key "menu_item_modifier_groups", "menu_items"
  add_foreign_key "menu_item_modifier_groups", "modifier_groups"
  add_foreign_key "menu_items", "categories"
  add_foreign_key "modifiers", "modifier_groups"
  add_foreign_key "order_discounts", "discount_rules"
  add_foreign_key "order_discounts", "orders"
  add_foreign_key "order_events", "orders"
  add_foreign_key "order_events", "users"
  add_foreign_key "order_item_modifiers", "modifiers"
  add_foreign_key "order_item_modifiers", "order_items"
  add_foreign_key "order_items", "combos"
  add_foreign_key "order_items", "menu_items"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "users"
  add_foreign_key "payments", "orders"
  add_foreign_key "payments", "users", column: "processed_by_user_id"
  add_foreign_key "print_logs", "orders"
  add_foreign_key "print_logs", "printers"
  add_foreign_key "purchase_order_items", "ingredients"
  add_foreign_key "purchase_order_items", "purchase_orders"
  add_foreign_key "purchase_orders", "suppliers"
  add_foreign_key "purchase_orders", "users"
  add_foreign_key "receipt_logs", "orders"
  add_foreign_key "recipes", "ingredients"
  add_foreign_key "recipes", "menu_items"
  add_foreign_key "shift_logs", "users"
  add_foreign_key "stock_adjustments", "ingredients"
  add_foreign_key "stock_adjustments", "stock_batches"
  add_foreign_key "stock_adjustments", "users"
  add_foreign_key "stock_batches", "ingredients"
  add_foreign_key "stock_batches", "suppliers"
  add_foreign_key "stock_take_items", "ingredients"
  add_foreign_key "stock_take_items", "stock_takes"
  add_foreign_key "stock_takes", "users"
  add_foreign_key "supplier_ingredients", "ingredients"
  add_foreign_key "supplier_ingredients", "suppliers"
  add_foreign_key "supplier_price_histories", "ingredients"
  add_foreign_key "supplier_price_histories", "suppliers"
  add_foreign_key "supplier_price_histories", "users", column: "recorded_by_user_id"
end
