# frozen_string_literal: true

# How the sale was settled: put on account (a receivable), or paid at the point of
# sale in cash or through a wallet. The treasury column records where paid-now
# money landed; this records how it got there, so takings can be reported by method.
class AddPaymentMethodToCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoices, :payment_method, :string, null: false, default: "on_account"
    add_index :customer_invoices, %i[company_id payment_method]
  end
end
