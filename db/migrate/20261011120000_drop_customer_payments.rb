# frozen_string_literal: true

# CustomerPayment was write-free from 2026-09-20 (Sales::RecordCustomerPaymentService
# writes a Voucher + PaymentAllocation instead) and, per production, had zero
# rows ever written to it. Nothing migrates here — there is nothing to migrate.
class DropCustomerPayments < ActiveRecord::Migration[7.1]
  def change
    drop_table "customer_payments", id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid "company_id", null: false
      t.uuid "customer_id", null: false
      t.uuid "user_id", null: false
      t.uuid "treasury_id", null: false
      t.bigint "amount_cents", null: false
      t.date "payment_date", null: false
      t.text "notes"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index ["company_id"], name: "index_customer_payments_on_company_id"
      t.index ["customer_id"], name: "index_customer_payments_on_customer_id"
      t.index ["treasury_id"], name: "index_customer_payments_on_treasury_id"
      t.index ["user_id"], name: "index_customer_payments_on_user_id"
    end
  end
end
