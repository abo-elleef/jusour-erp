# frozen_string_literal: true

# Rounding adjustment is retired — courier freight is a linked Expense, and
# invoice totals are lines minus discount only. Stored total_cents on existing
# rows are left as-is until the invoice is edited/saved again.
class RemoveAdjustmentCentsFromVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    remove_column :vendor_invoices, :adjustment_cents, :integer, default: 0, null: false
  end
end
