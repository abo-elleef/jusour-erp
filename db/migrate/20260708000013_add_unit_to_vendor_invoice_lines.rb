# frozen_string_literal: true

class AddUnitToVendorInvoiceLines < ActiveRecord::Migration[7.1]
  def change
    # The unit the buyer entered the quantity in (e.g. "gallon").
    # Null means the line was recorded in the ingredient's base unit.
    add_column :vendor_invoice_lines, :unit, :string
  end
end
