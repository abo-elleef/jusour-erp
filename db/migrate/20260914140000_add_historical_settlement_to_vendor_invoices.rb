# frozen_string_literal: true

# Before supplier payments were forced through invoices, a "direct AP payment"
# moved a supplier's AP balance without touching any invoice. By 2026-09 that had
# left the invoice list claiming 1,300,385.52 owed while the AP ledgers said
# 431,461.23 — 868,924.29 of invoices that read as unpaid but had in fact been
# paid, across 11 of 13 active suppliers.
#
# The cash for those invoices is already recorded: an Expense left the treasury
# and the AP ledger already dropped. What is missing is only the link back to the
# invoice. `historical_settled_cents` records that link without moving money —
# it joins amount_paid_cents and credit_applied_cents as a third way an invoice
# gets settled, so balance_due stays plain arithmetic on a loaded row.
#
# Partial by design: the invoice where a supplier's payments run out keeps the
# remainder open, which is what makes the open invoices add back up to the AP
# balance exactly.
class AddHistoricalSettlementToVendorInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :vendor_invoices, :historical_settled_cents, :integer, null: false, default: 0
    add_column :vendor_invoices, :historical_settled_at, :datetime
    add_reference :vendor_invoices, :historical_settled_by, type: :uuid, null: true,
      foreign_key: { to_table: :users }, index: true
  end
end
