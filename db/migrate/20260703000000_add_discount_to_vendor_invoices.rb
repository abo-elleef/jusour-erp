# frozen_string_literal: true

class AddDiscountToVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    change_table :vendor_invoices, bulk: true do |t|
      t.string :discount_type
      t.decimal :discount_value, precision: 10, scale: 2
      t.text :discount_notes
    end
  end
end
