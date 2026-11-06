# frozen_string_literal: true

# A finalized month. Finalizing credits the employee's own account with what
# they earned (net_pay_cents) — that is the whole accounting effect. Money only
# moves through vouchers: the one issued here when the month is paid out on
# finalize (payout_voucher, remaining_pay_cents, treasury, paid_on), and any
# other voucher to or from the employee before or after.
#
# The payout can be dated after the month ends — salaries are usually paid on
# the 3rd or 4th of the next month, once attendance, bonuses and penalties are
# settled. The accrual stays on the payroll month's last day; only the voucher
# (and the treasury) carries the real payment date. A late payout still counts
# as that payroll month's payment (Voucher.for_staff_month).
#
# advances_cents is what was paid to the employee during the month (vouchers
# out less vouchers in) at the moment of finalizing — kept for the record, not
# deducted from anything; the account balance already reflects it.
class PayrollSnapshot < ApplicationRecord
  include Tenantable

  belongs_to :user
  belongs_to :finalized_by, class_name: "User"
  belongs_to :treasury, optional: true
  belongs_to :payout_voucher, class_name: "Voucher", optional: true
  has_many :treasury_transactions, as: :source_record, dependent: :destroy

  validates :payroll_month, presence: true
  validates :user_id, uniqueness: { scope: :payroll_month }
  validates :base_salary_cents, :daily_rate_cents, :penalties_cents, :bonuses_cents, :net_pay_cents,
    :remaining_pay_cents, :penalties_waived_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :advances_cents, :staff_meals_cents, numericality: { only_integer: true }
  validates :finalized_at, presence: true
  validate :treasury_required_when_remaining_pay
  validate :paid_on_not_before_payroll_month

  before_validation :normalize_payroll_month

  def payout_required?
    remaining_pay_cents.positive?
  end

  # Paid when it was finalized, or paid out later. remaining_pay_cents is what
  # went to them; a month recorded to pay later keeps it at zero until then.
  # (Months paid before payouts were vouchers have no voucher, only this.)
  def paid_out?
    remaining_pay_cents.positive?
  end

  # What a month recorded with "pay later" still owes, as finalizing would
  # have paid it (see MonthlyPayrollService.payout_for): the month's pay, plus
  # anything owed to them from before, less what was paid to them or eaten
  # during the month. Money they owe the company from earlier months is not
  # kept back; it is repaid separately.
  #
  # Less anything paid to them since the month ended — vouchers and staff
  # meals, but not later months' salaries — so a month already paid by hand is
  # never paid twice, and an advance or meal early in the new month, before
  # payday, comes off this payout too.
  def payout_due_cents(on: Date.current)
    return 0 if paid_out?

    month_end = payroll_month.end_of_month
    balance_before = user.staff_balance_cents(as_of: month_end) - net_pay_cents
    due = ::Accounting::MonthlyPayrollService.payout_for(
      balance_before_cents: balance_before,
      net_pay_cents: net_pay_cents,
      month_payments_cents: advances_cents.to_i + staff_meals_cents.to_i
    ).payout_cents
    paid_since = [movement_since_month_end_cents(month_end, on.to_date), 0].min
    (due + paid_since).clamp(0..)
  end

  scope :for_month, ->(month) { where(payroll_month: month.to_date.beginning_of_month) }
  # Paid out in a later month than the one it pays for.
  scope :paid_late, lambda {
    joins(:payout_voucher).where("vouchers.voucher_date > (payroll_snapshots.payroll_month + INTERVAL '1 month' - INTERVAL '1 day')::date")
  }

  private

  def movement_since_month_end_cents(month_end, on)
    return 0 unless on > month_end

    lines = user.staff_account_lines
                .where(journal_entries: { date: (month_end + 1)..on })
                .where.not(journal_entries: { source_record_type: "PayrollSnapshot" })
    lines.sum(:credit_cents) - lines.sum(:debit_cents)
  end

  def normalize_payroll_month
    return if payroll_month.blank?

    self.payroll_month = payroll_month.to_date.beginning_of_month
  end

  def treasury_required_when_remaining_pay
    return unless payout_required?

    errors.add(:treasury, :blank) if treasury.blank?
    errors.add(:paid_on, :blank) if paid_on.blank?
  end

  def paid_on_not_before_payroll_month
    return if paid_on.blank? || payroll_month.blank?
    return if paid_on >= payroll_month.beginning_of_month

    errors.add(:paid_on, :before_payroll_month)
  end
end
