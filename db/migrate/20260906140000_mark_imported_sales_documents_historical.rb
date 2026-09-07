# frozen_string_literal: true

# Sales history imported from the previous system first landed as `draft`, which
# was the wrong shape: a draft is an unfinished sale awaiting confirmation, while
# these are completed sales that predate the system. `historical` says exactly
# that — counted by sales reporting, never posted to the ledger or to stock.
#
# Raw SQL on purpose: a migration must not depend on model code that will keep
# changing after it has run.
class MarkImportedSalesDocumentsHistorical < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE customer_invoices SET status = 'historical'
      WHERE legacy_number IS NOT NULL AND status = 'draft'
    SQL
    execute <<~SQL
      UPDATE credit_notes SET status = 'historical'
      WHERE legacy_number IS NOT NULL AND status = 'draft'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE customer_invoices SET status = 'draft'
      WHERE legacy_number IS NOT NULL AND status = 'historical'
    SQL
    execute <<~SQL
      UPDATE credit_notes SET status = 'draft'
      WHERE legacy_number IS NOT NULL AND status = 'historical'
    SQL
  end
end
