# frozen_string_literal: true

# Delivery could only ever be paid in cash at receive time: it lived solely as a
# linked Expense with a treasury. When the vendor bills delivery on the invoice and
# the whole thing is settled later, the amount has to be a liability to that vendor
# instead — which means it has to reach total_cents, since that is what drives
# supplier AP and balance due.
#
# The amount now lives on the invoice in both cases so there is one source of truth;
# freight_on_account decides whether it is owed to the vendor or already paid out.
class AddFreightOnAccountToVendorInvoices < ActiveRecord::Migration[7.1]
  def up
    add_column :vendor_invoices, :freight_amount_cents, :integer, default: 0, null: false
    add_column :vendor_invoices, :freight_on_account, :boolean, default: false, null: false

    # Backfill from the existing delivery Expense. Raw SQL on purpose — a migration
    # must not depend on app models. Scoped to the delivery category rather than
    # trusting that nothing else is ever sourced to an invoice.
    execute <<~SQL
      UPDATE vendor_invoices vi
      SET freight_amount_cents = e.amount_cents
      FROM expenses e
      JOIN expense_categories ec ON ec.id = e.expense_category_id
      WHERE e.source_record_type = 'VendorInvoice'
        AND e.source_record_id = vi.id
        AND ec.name = 'Goods delivery'
        AND e.amount_cents > 0
    SQL
  end

  def down
    remove_column :vendor_invoices, :freight_on_account
    remove_column :vendor_invoices, :freight_amount_cents
  end
end
