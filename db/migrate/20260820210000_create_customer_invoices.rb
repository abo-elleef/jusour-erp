# frozen_string_literal: true

# Step 2 slice 2: B2B sales invoices (the customer-side mirror of vendor invoices).
# A draft is built, then CONFIRMED — which raises AR and deducts stock. Prices are
# firm at sale (Option A); landed cost never touches these.
class CreateCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    create_table :customer_invoices, id: :uuid do |t|
      t.references :company,  type: :uuid, null: false, index: true
      t.references :customer, type: :uuid, null: false, index: true
      t.references :user,     type: :uuid, null: false, index: true
      t.references :location, type: :uuid, null: false, index: true
      t.string  :invoice_number, null: false
      t.date    :invoice_date, null: false
      t.string  :status, default: "draft", null: false
      t.string  :payment_status, default: "unpaid", null: false
      t.bigint  :total_cents, default: 0, null: false
      t.bigint  :amount_paid_cents, default: 0, null: false
      t.datetime :confirmed_at
      t.text    :notes
      t.timestamps
    end
    add_index :customer_invoices, %i[company_id invoice_number], unique: true
    add_index :customer_invoices, %i[company_id status]

    create_table :customer_invoice_lines, id: :uuid do |t|
      t.references :customer_invoice, type: :uuid, null: false, index: true
      t.references :ingredient, type: :uuid, null: false, index: true
      t.uuid    :unit_id
      t.decimal :quantity, precision: 12, scale: 3, null: false
      t.bigint  :unit_price_cents, default: 0, null: false
      t.bigint  :line_total_cents, default: 0, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
  end
end
