# frozen_string_literal: true

module Accounting
  class FinalizePayrollService
    def initialize(user, payroll_month, finalized_by:)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @finalized_by = finalized_by
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
        finalized_by: @finalized_by,
        finalized_at: Time.current
      )
      snapshot.save!
      snapshot
    end
  end
end
