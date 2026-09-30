# frozen_string_literal: true

# A model that owns a real ledger account — a persisted or (for Treasury)
# computed account_code, and enough about itself (name, type, normal side)
# that a caller never has to hand-type "asset"/"liability" next to it and
# hope the two stay matched.
#
# Default #to_account assembles an Accounting::AccountRef from the four
# component methods every includer defines: #account_code, #account_name,
# #account_type, #normal_balance. Supplier and Customer override #to_account
# directly instead, because their account is really their AP/AR treasury's —
# they have nothing of their own to report.
#
# Adding a type here is a decision, same as Partyable/PaymentAllocation#settles:
# it needs the four methods (or a #to_account override), and JournalEntryService
# picks it up automatically — no dispatch to update anywhere.
module Accountable
  extend ActiveSupport::Concern

  def to_account
    Accounting::AccountRef.new(
      code: account_code, name: account_name, account_type: account_type,
      normal_balance: normal_balance, treasury_id: account_treasury_id
    )
  end

  # Only a real treasury movement carries this — every other Accountable
  # leaves it nil. Treasury overrides it to return its own id.
  def account_treasury_id
    nil
  end
end
