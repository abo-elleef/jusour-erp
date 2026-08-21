# frozen_string_literal: true

# Links a price-history row back to the invoice line that produced it, so
# reversing that line (an invoice edit) can remove the row instead of leaving a
# stale price behind next to the corrected one. Without the link, a correction
# reads as a genuine price change on the trend page.
#
# Nullify rather than cascade: an unlinked row is still valid history, and rows
# recorded before this migration keep their NULL.
class AddVendorInvoiceLineToSupplierPriceHistories < ActiveRecord::Migration[7.1]
  def change
    add_reference :supplier_price_histories, :vendor_invoice_line,
      type: :uuid, null: true, index: true,
      foreign_key: { on_delete: :nullify }
  end
end
