# frozen_string_literal: true

# Sales may now type a line's unit price. list_price_cents is the price the
# form auto-filled (the product's selling price at the time); price_overridden
# marks a line whose price differs from it. Existing lines keep a NULL list
# price and false, so old and imported invoices never show as edited.
class AddPriceOverrideToCustomerInvoiceLines < ActiveRecord::Migration[7.1]
  def change
    add_column :customer_invoice_lines, :list_price_cents, :bigint
    add_column :customer_invoice_lines, :price_overridden, :boolean, default: false, null: false
  end
end
