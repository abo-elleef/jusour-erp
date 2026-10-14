# frozen_string_literal: true

class AddFulfillmentToCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoices, :fulfillment_method, :string, null: false, default: "pickup"
    add_column :customer_invoices, :shipping_company_id, :uuid
    add_column :customer_invoices, :dispatched_at, :datetime
    add_column :customer_invoices, :sales_payment_method_id, :uuid

    add_index :customer_invoices, %i[company_id fulfillment_method]
    add_index :customer_invoices, :shipping_company_id
    add_index :customer_invoices, :sales_payment_method_id
  end
end
