# frozen_string_literal: true

# A sale paid at the counter never becomes a receivable: the money goes straight
# into a treasury. Recording which one is what separates a cash sale from a credit
# sale, so the confirm step knows whether to raise AR or to bank the money.
class AddTreasuryToCustomerInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :customer_invoices, :treasury, type: :uuid, null: true, foreign_key: true
  end
end
