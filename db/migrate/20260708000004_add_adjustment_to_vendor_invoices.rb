# frozen_string_literal: true

class AddAdjustmentToVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :vendor_invoices, :adjustment_cents, :integer, default: 0, null: false
  end
end
