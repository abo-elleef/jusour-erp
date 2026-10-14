# frozen_string_literal: true

class AddDeliveryFeeToCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoices, :delivery_fee_cents, :integer, null: false, default: 0
    add_column :customer_invoices, :standard_delivery_fee_cents, :integer, null: false, default: 0
  end
end
