# frozen_string_literal: true

class AddLineTotalCentsToVendorInvoiceLines < ActiveRecord::Migration[7.1]
  def up
    add_column :vendor_invoice_lines, :line_total_cents, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE vendor_invoice_lines
      SET line_total_cents = ROUND(quantity * unit_price_cents)
    SQL
  end

  def down
    remove_column :vendor_invoice_lines, :line_total_cents
  end
end
