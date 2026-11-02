# frozen_string_literal: true

require "rails_helper"

# Penalties come out of what the month leaves after its own advances and never
# push the account below zero; the rest is waived — see
# MonthlyPayrollService.penalties_waived_for.
RSpec.describe "Waiving penalties that would leave a negative balance" do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 1_000_000, balance_cents: 1_000_000)
  end
  let(:month) { Date.new(2026, 6, 1) }

  before { Current.company = company }
  around { |example| travel_to(Time.zone.local(2026, 6, 20, 10)) { example.run } }

  def advance!(cents, date: Date.new(2026, 6, 10))
    Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: safe, user: owner, amount_cents: cents,
      voucher_date: date, party_type: "User", party_id: staff.id
    ).call
  end

  def penalty!(cents, payroll_month: month)
    PayrollAdjustment.create!(user: staff, recorded_by: owner, kind: "penalty", unit_type: "fixed",
                              amount_cents: cents, payroll_month: payroll_month, happened_at: payroll_month)
  end

  def finalize!(payroll_month = month, **opts)
    Accounting::FinalizePayrollService.new(staff, payroll_month, finalized_by: owner, **opts).call
  end

  describe ".penalties_waived_for" do
    def waived(penalties, earned, payments)
      Accounting::MonthlyPayrollService.penalties_waived_for(
        penalties_cents: penalties, earned_cents: earned, month_payments_cents: payments
      )
    end

    it "waives nothing when the month covers advances and penalties" do
      expect(waived(18_000, 79_500, 50_000)).to eq(0)
    end

    it "waives only the part that would go below zero" do
      expect(waived(18_000, 79_500, 70_000)).to eq(8_500)
    end

    it "waives all of it when advances already take the whole month" do
      expect(waived(18_000, 79_500, 90_000)).to eq(18_000)
    end
  end

  context "when advances plus penalties exceed the month's pay" do
    before do
      advance!(250_000)
      penalty!(100_000)
    end

    it "previews the waiver and a zero balance" do
      summary = staff.monthly_payroll(month)

      expect(summary.penalties_cents).to eq(100_000)
      expect(summary.penalties_waived_cents).to eq(50_000)
      expect(summary.net_pay_cents).to eq(250_000)
      expect(summary.remaining_pay_cents).to eq(0)
    end

    it "finalizes at zero, storing what was waived" do
      snapshot = finalize!

      expect(snapshot.penalties_cents).to eq(100_000)
      expect(snapshot.penalties_waived_cents).to eq(50_000)
      expect(snapshot.net_pay_cents).to eq(250_000)
      expect(staff.staff_balance_cents).to eq(0)
    end

    it "carries the penalties as debt when the waiver is turned off" do
      snapshot = finalize!(waive_penalties: false)

      expect(snapshot.penalties_waived_cents).to eq(0)
      expect(snapshot.net_pay_cents).to eq(200_000)
      expect(staff.staff_balance_cents).to eq(-50_000)
    end
  end

  it "leaves an advance larger than the month as debt, but waives every penalty" do
    advance!(350_000)
    penalty!(40_000)

    snapshot = finalize!

    expect(snapshot.penalties_waived_cents).to eq(40_000)
    expect(staff.staff_balance_cents).to eq(-50_000)
  end

  it "still penalizes someone repaying an earlier month's advance" do
    advance!(400_000, date: Date.new(2026, 5, 10))
    finalize!(Date.new(2026, 5, 1))
    penalty!(40_000)

    summary = staff.monthly_payroll(month)

    expect(summary.penalties_waived_cents).to eq(0)
    expect(summary.net_pay_cents).to eq(260_000)
  end
end
