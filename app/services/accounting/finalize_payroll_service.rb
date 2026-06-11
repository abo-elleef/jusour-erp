# frozen_string_literal: true

module Accounting
  class FinalizePayrollService
    def initialize(user, payroll_month, finalized_by:, treasury: nil, paid_on: nil)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @finalized_by = finalized_by
      @treasury = treasury
      @paid_on = paid_on
    end

    def call
      summary = MonthlyPayrollService.new(@user, @payroll_month).build_calculated

      snapshot = PayrollSnapshot.find_or_initialize_by(user: @user, payroll_month: @payroll_month)
      snapshot.assign_attributes(
        base_salary_cents: summary.base_salary_cents,
        daily_rate_cents: summary.daily_rate_cents,
        penalties_cents: summary.penalties_cents,
        bonuses_cents: summary.bonuses_cents,
        net_pay_cents: summary.net_pay_cents,
        advances_cents: summary.advances_cents,
        remaining_pay_cents: summary.remaining_pay_cents,
        treasury: summary.remaining_pay_cents.positive? ? @treasury : nil,
        paid_on: summary.remaining_pay_cents.positive? ? resolve_paid_on : nil,
        finalized_by: @finalized_by,
        finalized_at: Time.current
      )

      ApplicationRecord.transaction do
        snapshot.save!
        TreasuryLedgerService.sync_payroll_salary!(snapshot)
      end

      snapshot
    end

    private

    def resolve_paid_on
      date = @paid_on.presence || Date.current
      date = date.to_date
      month_start = @payroll_month.beginning_of_month
      month_end = @payroll_month.end_of_month
      date.clamp(month_start, month_end)
    end
  end
end
