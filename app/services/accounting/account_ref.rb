# frozen_string_literal: true

module Accounting
  # What JournalEntryService's debit/credit actually consume: an account that
  # fully describes itself. Before this, every call site handed a bare
  # {code:, name:} hash *and* separately typed "asset"/"liability"/etc. by
  # hand — nothing tied the two together, so a mismatched string next to the
  # wrong code would post silently. An Accountable's #to_account returns one
  # of these instead, so the account says what it is.
  AccountRef = Struct.new(:code, :name, :account_type, :normal_balance, :treasury_id, keyword_init: true) do
    # Already an account — every caller of #to_account (Accountable's
    # default, debit/credit's line_for) can call it unconditionally without
    # checking whether it already has an AccountRef or something that builds one.
    def to_account = self
  end
end
