# frozen_string_literal: true

module Accounting
  class PayPayrollAdvanceService
    def initialize(user:, amount_cents:, treasury:, paid_by:, paid_on: Date.current, notes: nil)
      @user = user
      @amount_cents = amount_cents
      @treasury = treasury
      @paid_by = paid_by
      @paid_on = paid_on
      @notes = notes
    end

    def call
      advance = PayrollAdvance.new(
        user: @user,
        amount_cents: @amount_cents,
        treasury: @treasury,
        paid_by: @paid_by,
        paid_on: @paid_on,
        notes: @notes
      )

      ApplicationRecord.transaction do
        advance.save!
        TreasuryLedgerService.sync_payroll_advance!(advance)
      end

      advance
    end
  end
end
