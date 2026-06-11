# frozen_string_literal: true

module Accounting
  class PayPayrollAdvanceService
    def initialize(user:, payroll_month:, advance_slot:, amount_cents:, treasury:, paid_by:, paid_on: Date.current, notes: nil)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @advance_slot = advance_slot
      @amount_cents = amount_cents
      @treasury = treasury
      @paid_by = paid_by
      @paid_on = paid_on
      @notes = notes
    end

    def call
      advance = PayrollAdvance.new(
        user: @user,
        payroll_month: @payroll_month,
        advance_slot: @advance_slot,
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
