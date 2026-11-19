# frozen_string_literal: true

# Shipping proof (Bazzar slice C): the courier's tracking number. The waybill
# photo is an Active Storage attachment, so it needs no column.
class AddShippingTrackingNumberToCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoices, :shipping_tracking_number, :string
  end
end
