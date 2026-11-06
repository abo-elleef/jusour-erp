# frozen_string_literal: true

module Accounting
  # Finalizing a month does one thing to the books: it credits the employee's
  # own account with what they earned (JournalEntryService#record_payroll_accrual!).
  # Whatever was paid to them before — and staff meals — already debited that
  # account.
  #
  # Given a treasury, it also pays them out with an ordinary payment voucher:
  # the month's pay (see MonthlyPayrollService.payout_for). Nothing is kept
  # back against money they owe the company; that is repaid separately by a
  # receipt voucher. Without a treasury it only records the month, and the
  # balance waits for a voucher.
  class FinalizePayrollService
    def initialize(user, payroll_month, finalized_by:, treasury: nil, paid_on: nil, waive_penalties: true)
      @waive_penalties = waive_penalties
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @finalized_by = finalized_by
      @treasury = treasury
      @paid_on = paid_on
    end

    def call
      snapshot = PayrollSnapshot.find_or_initialize_by(user: @user, payroll_month: @payroll_month)

      ApplicationRecord.transaction do
        snapshot.payout_voucher&.void!(user: @finalized_by, reason: :source_removed)
        JournalEntryService.destroy_for_source!(snapshot) if snapshot.persisted?
        # After the old payout is voided, so re-finalizing doesn't count it as
        # paid during the month.
        summary = MonthlyPayrollService.new(@user, @payroll_month, waive_penalties: @waive_penalties).build_calculated
        balance_before = @user.staff_balance_cents(as_of: @payroll_month.end_of_month)

        snapshot.assign_attributes(
          base_salary_cents: summary.base_salary_cents,
          attendance_pay_cents: summary.attendance_pay_cents,
          payable_days: summary.payable_days,
          bonus_days: summary.bonus_days,
          penalty_days: summary.penalty_days,
          daily_rate_cents: summary.daily_rate_cents,
          penalties_cents: summary.penalties_cents,
          penalties_waived_cents: summary.penalties_waived_cents,
          bonuses_cents: summary.bonuses_cents,
          # Penalties can exceed the month's pay. The employee doesn't end up
          # owing for a month's work, so the accrual floors at zero.
          net_pay_cents: [summary.net_pay_cents, 0].max,
          advances_cents: summary.paid_cents,
          staff_meals_cents: summary.staff_meals_cents,
          remaining_pay_cents: 0,
          deduction_cents: 0,
          treasury: nil,
          paid_on: nil,
          payout_voucher: nil,
          finalized_by: @finalized_by,
          finalized_at: Time.current
        )
        snapshot.save!
        JournalEntryService.record_payroll_accrual!(snapshot)

        payout = MonthlyPayrollService.payout_for(
          balance_before_cents: balance_before, net_pay_cents: snapshot.net_pay_cents,
          month_payments_cents: summary.paid_cents + summary.staff_meals_cents
        )
        pay_out!(snapshot, payout.payout_cents) if @treasury
      end

      snapshot
    end

    private

    # Pays the month's pay less what they already had during the month.
    def pay_out!(snapshot, owed)
      return unless owed.positive?

      PayOutPayrollService.new(snapshot, treasury: @treasury, paid_by: @finalized_by,
                                         paid_on: @paid_on, amount_cents: owed).call
    end
  end
end
