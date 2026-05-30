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

ActiveRecord::Schema[7.1].define(version: 2026_05_30_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

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

  create_table "customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.integer "loyalty_points", default: 0, null: false
    t.integer "total_spent_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
    t.index ["phone"], name: "index_customers_on_phone", unique: true
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

  create_table "gift_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", null: false
    t.integer "balance_cents", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_gift_cards_on_code", unique: true
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
    t.uuid "menu_item_id", null: false
    t.string "name", null: false
    t.boolean "required", default: false, null: false
    t.boolean "multi_select", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id"], name: "index_modifier_groups_on_menu_item_id"
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

  create_table "settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "combo_items", "combos"
  add_foreign_key "combo_items", "menu_items"
  add_foreign_key "loyalty_transactions", "customers"
  add_foreign_key "loyalty_transactions", "orders"
  add_foreign_key "menu_items", "categories"
  add_foreign_key "modifier_groups", "menu_items"
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
  add_foreign_key "receipt_logs", "orders"
end
