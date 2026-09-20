# frozen_string_literal: true

# Renders the name of a ledger account the way the reader's locale wants it.
#
# A journal line stores `account_name` as it stood when the entry was written.
# For a treasury or an expense category that is exactly right — the name is
# data, and a statement should not rewrite history because someone renamed a
# safe. For the accounts the app names itself it is wrong: those names are
# translations, so a line posted from the English UI would read "Accrued
# expenses" to an Arabic reader, next to a treasury shown in Arabic.
#
# So system accounts are resolved by code at render time and everything else
# falls back to what was stored.
module LedgerAccountNamesHelper
  def ledger_account_name(code, fallback = nil)
    ::Accounting::JournalEntryService.account_display_name(code, fallback)
  end

  # Convenience for the common case of a JournalEntryLine.
  def ledger_line_account_name(line)
    ledger_account_name(line.account_code, line.account_name)
  end
end
