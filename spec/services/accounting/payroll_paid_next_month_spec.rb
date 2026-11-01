# frozen_string_literal: true

require "rails_helper"

# Salaries are usually paid on the 3rd or 4th of the next month, once
# attendance, bonuses and penalties are settled. The accrual stays on the
# payroll month's last day; the voucher and the treasury carry the real
# payment date, and the payout still counts as the payroll month's.
RSpec.describe "Paying a month's payroll after it ends" do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) { create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000, pin: "1234") }
  let(:treasury) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 1_000_000, balance_cents: 1_000_000)
  end
  let(:october) { Date.new(2026, 10, 1) }
  let(:november) { Date.new(2026, 11, 1) }
  let(:paid_on) { Date.new(2026, 11, 3) }

  before do
    Current.company = company
    travel_to Time.zone.local(2026, 11, 5, 12)
  end

  after { travel_back }

  def finalize(paid_on: self.paid_on)
    Accounting::FinalizePayrollService.new(staff, october, finalized_by: owner,
                                           treasury: treasury, paid_on: paid_on).call
  end

  it "dates the voucher and the treasury on the payment day and the accrual on the month's last day" do
    snapshot = finalize

    expect(snapshot.paid_on).to eq(paid_on)
    expect(snapshot.payout_voucher.voucher_date).to eq(paid_on)
    expect(TreasuryTransaction.where(treasury: treasury).pluck(:occurred_on)).to all(eq(paid_on))
    expect(JournalEntry.for_source(snapshot).first.date).to eq(october.end_of_month)
    expect(JournalEntry.for_source(snapshot.payout_voucher).first.date).to eq(paid_on)
  end

  it "owes the salary on the month's last day and settles it on the payment day" do
    finalize

    expect(staff.staff_balance_cents(as_of: october.end_of_month)).to eq(300_000)
    expect(staff.staff_balance_cents(as_of: paid_on)).to eq(0)
  end

  it "counts the payout in the payroll month, not the month it's dated in" do
    finalize

    oct = Accounting::MonthlyPayrollService.new(staff, october).call
    expect(oct.paid_cents).to eq(300_000)
    expect(oct.remaining_pay_cents).to eq(0)

    nov = Accounting::MonthlyPayrollService.new(staff, november).build_calculated
    expect(nov.paid_cents).to eq(0)
    expect(nov.payments).to be_empty
  end

  it "shows the payout under the payroll month in the money-paid-to-staff report" do
    finalize
    users = User.where(id: staff.id)

    oct = Accounting::StaffPaymentsReportService.new(october, users: users)
    nov = Accounting::StaffPaymentsReportService.new(november, users: users)

    expect(oct.total(:paid_out_cents)).to eq(300_000)
    expect(nov.total(:paid_out_cents)).to eq(0)
    expect(nov.vouchers).to be_empty
  end

  it "still counts other November vouchers in November" do
    finalize
    Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: treasury, user: owner,
                                         amount_cents: 50_000, voucher_date: Date.new(2026, 11, 4),
                                         party_type: "User", party_id: staff.id).call

    expect(staff.staff_paid_cents_for_month(november)).to eq(50_000)
    expect(staff.staff_paid_cents_for_month(october)).to eq(300_000)
  end

  it "re-finalizing voids the late payout and doesn't count it as paid during the month" do
    first = finalize
    old_voucher = first.payout_voucher

    snapshot = finalize(paid_on: Date.new(2026, 11, 4))

    expect(old_voucher.reload.voided_at).to be_present
    expect(snapshot.advances_cents).to eq(0)
    expect(snapshot.payout_voucher.voucher_date).to eq(Date.new(2026, 11, 4))
    expect(treasury.reload.balance_cents).to eq(700_000)
  end

  it "does not allow a payment date before the payroll month" do
    snapshot = PayrollSnapshot.new(user: staff, payroll_month: october, paid_on: Date.new(2026, 9, 30))
    snapshot.valid?
    expect(snapshot.errors.details[:paid_on]).to include(error: :before_payroll_month)
  end
end
