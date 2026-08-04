# frozen_string_literal: true

module Admin
  module Accounting
    class BaseController < Admin::BaseController
      include SessionDateRange

      before_action :authorize_accounting!

      private

      # Permission-based section gate: each accounting controller requires its
      # mapped permission (AccountingNav), so e.g. a sub-manager reaches Attendance
      # (attendance:log) but not the ledgers (accounting:ledgers).
      def authorize_accounting!
        permission = AccountingNav.permission_for(controller_name)
        raise Pundit::NotAuthorizedError if permission.nil? || !current_user.can?(permission)
      end

      # For each JE line that targets a treasury, apply the balance delta and
      # create a TreasuryTransaction so the treasury stays in sync with the ledger.
      # Amount direction: asset treasury → debit_cents - credit_cents (DR=in, CR=out)
      #                   AP treasury    → credit_cents - debit_cents
      def sync_je_treasuries!(je)
        je.lines.each do |line|
          next if line.treasury_id.blank?

          treasury = Treasury.lock.find(line.treasury_id)
          amount_cents = if treasury.treasury_type == "supplier_ap"
                           line.credit_cents - line.debit_cents
                         else
                           line.debit_cents - line.credit_cents
                         end
          next if amount_cents.zero?

          treasury.apply_balance_delta!(amount_cents)
          TreasuryTransaction.create!(
            treasury:            treasury,
            user:                je.created_by,
            amount_cents:        amount_cents,
            kind:                "journal_entry",
            description:         je.description,
            occurred_on:         je.date,
            source_record:       je,
            balance_after_cents: treasury.balance_cents
          )
        end
      end
    end
  end
end
