# frozen_string_literal: true

# Step 2 slice 3: customer payments against AR. Cash comes INTO a treasury and
# the payment is allocated FIFO across the customer's outstanding invoices.
class CreateCustomerPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :customer_payments, id: :uuid do |t|
      t.references :company,  type: :uuid, null: false, index: true
      t.references :customer, type: :uuid, null: false, index: true
      t.references :user,     type: :uuid, null: false, index: true
      t.references :treasury, type: :uuid, null: false, index: true
      t.bigint :amount_cents, null: false
      t.date   :payment_date, null: false
      t.text   :notes
      t.timestamps
    end
  end
end
