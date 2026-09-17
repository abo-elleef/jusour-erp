# frozen_string_literal: true

# Which payment settled which invoice, and for how much.
#
# Nothing recorded this before. On the supplier side the link was implicit —
# a VendorInvoicePayment belongs to one invoice — but on the customer side a
# payment belongs to a *customer*, and Sales::RecordCustomerPaymentService
# spread it across their outstanding invoices oldest-first while writing the
# split down nowhere. It only ever bumped each invoice's amount_paid_cents, so
# "which receipt cleared invoice SI-2026-00471?" had no answer.
#
# `payment` is polymorphic because the payer differs by side today
# (CustomerPayment / VendorInvoicePayment) and because a voucher will become one
# later. `settles` is polymorphic for the same reason: invoices now, and expenses,
# incomes, advances and loans once vouchers can settle them.
#
# A payment's unallocated remainder is not stored — it is the payment amount less
# its allocations, which is what "on account" means.
class CreatePaymentAllocations < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_allocations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid   :company_id,   null: false
      t.string :payment_type, null: false
      t.uuid   :payment_id,   null: false
      t.string :settles_type, null: false
      t.uuid   :settles_id,   null: false
      t.bigint :amount_cents, null: false

      t.timestamps
    end

    add_index :payment_allocations, :company_id
    add_index :payment_allocations, %i[payment_type payment_id],
              name: "index_payment_allocations_on_payment"
    add_index :payment_allocations, %i[settles_type settles_id],
              name: "index_payment_allocations_on_settles"
    # One payment settles a given invoice once; a second application against the
    # same pair would be a bug, not a partial top-up.
    add_index :payment_allocations, %i[payment_type payment_id settles_type settles_id],
              unique: true, name: "index_payment_allocations_unique_pair"

    add_foreign_key :payment_allocations, :companies
  end
end
