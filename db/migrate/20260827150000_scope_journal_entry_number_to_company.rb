# frozen_string_literal: true

# Journal entry numbers are generated PER COMPANY (JournalEntry.next_entry_number
# takes a company_id), but the unique index was global — so a second tenant
# generating "JE-2026-00042" from its own sequence collided with another tenant
# that already held that number, and the entry failed to save.
#
# Every other document in the app numbers per company (VI-, SI-, CN-, SHP-, MFG-);
# this makes journal entries consistent. Widening a global unique index to a
# composite one is a strictly weaker constraint, so existing rows still fit.
class ScopeJournalEntryNumberToCompany < ActiveRecord::Migration[7.1]
  def change
    remove_index :journal_entries, :entry_number, unique: true,
      name: "index_journal_entries_on_entry_number"
    add_index :journal_entries, %i[company_id entry_number], unique: true,
      name: "index_journal_entries_on_company_id_and_entry_number"
  end
end
