# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::MonthlyPayrollService do
  include ActiveSupport::Testing::TimeHelpers
  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000, pin: "1234")
  end
  let(:payroll_month) { Date.current.beginning_of_month }

  before { Current.company = company }

  describe "attendance integration" do
    def present_status = company.attendance_statuses.find_by!(code: "present")

    it "falls back to the full salary when no attendance is recorded" do
      result = described_class.new(staff, payroll_month).call
      expect(result.attendance_recorded).to be(false)
      expect(result.attendance_pay_cents).to eq(300_000)
      expect(result.net_pay_cents).to eq(300_000)
    end

    it "drives net pay from recorded attendance" do
      15.times do |i|
        StaffAttendance.create!(company: company, user: staff, recorded_by: owner,
                                attendance_status: present_status, date: payroll_month + i.days)
      end
      result = described_class.new(staff, payroll_month).call
      expect(result.attendance_recorded).to be(true)
      expect(result.payable_days).to eq(15)
      expect(result.attendance_pay_cents).to eq(150_000) # 15 * (300_000 / 30)
      expect(result.net_pay_cents).to eq(150_000)
    end
  end

  describe "#call" do
    it "returns calculated payroll when no snapshot exists" do
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "fixed",
        amount_cents: 10_000,
        payroll_month: payroll_month,
        happened_at: payroll_month
      )

      result = described_class.new(staff, payroll_month).call

      expect(result.finalized).to be(false)
      expect(result.base_salary_cents).to eq(300_000)
      expect(result.penalties_cents).to eq(10_000)
      expect(result.net_pay_cents).to eq(290_000)
      expect(result.advances_cents).to eq(0)
      expect(result.remaining_pay_cents).to eq(290_000)
    end

    it "subtracts advances from remaining pay" do
      treasury = Treasury.create!(
        company: company,
        name: "Safe",
        treasury_type: "safe",
        opening_balance_cents: 500_000,
        balance_cents: 500_000
      )

      Accounting::PayPayrollAdvanceService.new(
        user: staff,
        amount_cents: 50_000,
        treasury: treasury,
        paid_by: owner,
        paid_on: payroll_month.change(day: 15)
      ).call

      result = described_class.new(staff, payroll_month).call

      expect(result.advances_cents).to eq(50_000)
      expect(result.remaining_pay_cents).to eq(250_000)
    end

    it "returns snapshot values when payroll is recorded" do
      PayrollAdjustment.create!(
        user: staff,
        recorded_by: owner,
        kind: "penalty",
        unit_type: "fixed",
        amount_cents: 10_000,
        payroll_month: payroll_month,
        happened_at: payroll_month
      )

      treasury = Treasury.create!(
        company: company,
        name: "Safe",
        treasury_type: "safe",
        opening_balance_cents: 500_000,
        balance_cents: 500_000
      )
      Accounting::FinalizePayrollService.new(
        staff,
        payroll_month,
        finalized_by: owner,
        treasury: treasury,
        paid_on: payroll_month.end_of_month
      ).call
      staff.update!(monthly_salary_cents: 500_000)

      result = described_class.new(staff, payroll_month).call

      expect(result.finalized).to be(true)
      expect(result.base_salary_cents).to eq(300_000)
      expect(result.net_pay_cents).to eq(290_000)
    end
  end

  describe ".sort_rows" do
    let(:low_row) do
      described_class.new(staff, payroll_month).build_calculated
    end
    let(:high_user) do
      create(:user, company: company, name: "Zara", monthly_salary_cents: 500_000)
    end
    let(:high_row) do
      described_class.new(high_user, payroll_month).build_calculated
    end

    it "sorts by net pay descending" do
      sorted = described_class.sort_rows([low_row, high_row], sort: "net_pay_cents", direction: "desc")

      expect(sorted.first.user.name).to eq("Zara")
    end
  end
end
