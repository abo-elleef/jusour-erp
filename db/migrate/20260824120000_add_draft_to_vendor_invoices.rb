# frozen_string_literal: true

# A save point while typing a long invoice. A draft posts nothing: no stock batches,
# no stock adjustments, no supplier AP, no journal entry, no price history — all of
# which are created by receive_line / record_invoice!, which a draft never reaches.
#
# Deliberately a separate flag rather than another payment_status: "draft" is a
# document state, not a payment state, and conflating them would let
# sync_payment_status! silently overwrite it.
class AddDraftToVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :vendor_invoices, :draft, :boolean, default: false, null: false
    add_index :vendor_invoices, %i[company_id draft]
  end
end
