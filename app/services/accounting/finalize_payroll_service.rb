# frozen_string_literal: true

module Accounting
  # Finalizing a month does one thing to the books: it credits the employee's
  # own account with what they earned (JournalEntryService#record_payroll_accrual!).
  # Whatever was paid to them during the month — and staff meals — already
  # debited that account, so the balance left afterwards is exactly what is
  # still owed.
  #
  # Given a treasury, it also pays that balance out, as an ordinary payment
  # voucher to the employee. Without one it only records the month, and the
  # balance waits for a voucher whenever the money is actually handed over.
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

      ApplicationRecord.transaction do
        snapshot.payout_voucher&.void!(user: @finalized_by, reason: :source_removed)

        snapshot.assign_attributes(
          base_salary_cents: summary.base_salary_cents,
          attendance_pay_cents: summary.attendance_pay_cents,
          payable_days: summary.payable_days,
          bonus_days: summary.bonus_days,
          penalty_days: summary.penalty_days,
          daily_rate_cents: summary.daily_rate_cents,
          penalties_cents: summary.penalties_cents,
          bonuses_cents: summary.bonuses_cents,
          # Penalties can exceed the month's pay. The employee doesn't end up
          # owing for a month's work, so the accrual floors at zero.
          net_pay_cents: [summary.net_pay_cents, 0].max,
          advances_cents: summary.paid_cents,
          staff_meals_cents: summary.staff_meals_cents,
          remaining_pay_cents: 0,
          treasury: nil,
          paid_on: nil,
          payout_voucher: nil,
          finalized_by: @finalized_by,
          finalized_at: Time.current
        )
        snapshot.save!
        JournalEntryService.record_payroll_accrual!(snapshot)

        pay_out!(snapshot) if @treasury
      end

      snapshot
    end

    private

    def pay_out!(snapshot)
      owed = @user.staff_balance_cents
      return unless owed.positive?

      paid_on = resolve_paid_on
      voucher = RecordVoucherService.new(
        direction: Voucher::PAYMENT,
        treasury: @treasury,
        user: @finalized_by,
        amount_cents: owed,
        voucher_date: paid_on,
        counterparty: @user.name,
        notes: I18n.t("accounting.treasuries.transactions.payroll_salary",
                      employee: @user.name,
                      month: I18n.l(@payroll_month, format: "%B %Y")),
        party_type: "User",
        party_id: @user.id
      ).call

      snapshot.update!(remaining_pay_cents: owed, treasury: @treasury, paid_on: paid_on, payout_voucher: voucher)
    end

    def resolve_paid_on
      date = @paid_on.presence || Date.current
      date.to_date.clamp(@payroll_month.beginning_of_month, @payroll_month.end_of_month)
    end
  end
end
