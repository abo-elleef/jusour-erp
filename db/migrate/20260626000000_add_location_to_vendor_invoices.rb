# frozen_string_literal: true

class AddLocationToVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :vendor_invoices, :location, foreign_key: true, type: :uuid
  end
end
