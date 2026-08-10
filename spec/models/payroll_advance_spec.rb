# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayrollAdvance, type: :model do
  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
  end
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Main Safe",
      treasury_type: "safe",
      opening_balance_cents: 1_000_000,
      balance_cents: 1_000_000
    )
  end
  let(:payroll_month) { Date.new(2026, 6, 1) }

  before do
    Current.company = company
    AttendanceStatus.seed_defaults!(company)
  end

  def mark_present(*days)
    status = company.attendance_statuses.find_by!(code: "present")
    days.each do |day|
      StaffAttendance.create!(
        company: company,
        user: staff,
        recorded_by: owner,
        date: Date.new(2026, 6, day),
        attendance_status: status
      )
    end
  end

  describe ".max_amount_cents_for" do
    it "caps by monthly salary even when attendance pay is lower" do
      mark_present(1, 2)
      attendance_pay = Accounting::MonthlyPayrollService.new(staff, payroll_month).build_calculated.net_pay_cents
      expect(attendance_pay).to be < 300_000

      expect(described_class.max_amount_cents_for(staff, payroll_month)).to eq(300_000)
    end

    it "subtracts advances already paid in the month" do
      Accounting::PayPayrollAdvanceService.new(
        user: staff,
        amount_cents: 100_000,
        treasury: treasury,
        paid_by: owner,
        paid_on: Date.new(2026, 6, 10)
      ).call

      expect(described_class.max_amount_cents_for(staff, payroll_month)).to eq(200_000)
    end
  end

  describe "within_advance_limits" do
    it "allows an advance up to monthly salary despite low attendance pay" do
      mark_present(1, 2, 3, 4, 5)

      advance = described_class.new(
        user: staff,
        amount_cents: 250_000,
        treasury: treasury,
        paid_by: owner,
        paid_on: Date.new(2026, 6, 15)
      )

      expect(advance).to be_valid
    end

    it "rejects an advance above monthly salary" do
      advance = described_class.new(
        user: staff,
        amount_cents: 300_001,
        treasury: treasury,
        paid_by: owner,
        paid_on: Date.new(2026, 6, 15)
      )

      expect(advance).not_to be_valid
      expect(advance.errors[:amount_cents]).to be_present
    end
  end
end
