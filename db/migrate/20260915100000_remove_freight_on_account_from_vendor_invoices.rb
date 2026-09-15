# frozen_string_literal: true

# Delivery billed on the invoice ("credit on account") is gone. Delivery is now
# only ever paid at receive as a linked Goods delivery Expense, or entered by the
# user as an ordinary invoice line. The flag never carried a non-zero amount, so
# no total, AP balance, or journal entry changes when it goes.
class RemoveFreightOnAccountFromVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    remove_column :vendor_invoices, :freight_on_account, :boolean, default: false, null: false
  end
end
