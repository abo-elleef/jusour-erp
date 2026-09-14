# frozen_string_literal: true

# A credit note reduced the supplier's AP treasury but nothing on the invoice it
# came from, so the two disagreed: the treasury said 9K owed while the invoice
# still showed a 10K balance due. Paying the invoice off in full then drove the
# AP treasury negative by the amount of the credit.
#
# Linking the note to its invoice lets the credit settle that invoice the same way
# a payment does. `credit_applied_cents` mirrors the existing `amount_paid_cents`
# denormalisation so balance-due stays plain arithmetic on a row already loaded.
#
# Existing notes are left unlinked — they only ever moved the supplier balance,
# and back-dating them onto invoices would silently re-open or close settled ones.
class LinkVendorCreditNotesToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :vendor_credit_notes, :vendor_invoice, type: :uuid, null: true,
      foreign_key: true, index: true
    add_column :vendor_invoices, :credit_applied_cents, :integer, null: false, default: 0
  end
end
