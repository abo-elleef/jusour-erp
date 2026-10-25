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

    it "drives net pay from recorded attendance for non-owner staff" do
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

    it "drives pay from attendance for managers and sub-managers" do
      manager = create(:user, :manager, company: company, monthly_salary_cents: 300_000)
      5.times do |i|
        StaffAttendance.create!(company: company, user: manager, recorded_by: owner,
                                attendance_status: present_status, date: payroll_month + i.days)
      end
      result = described_class.new(manager, payroll_month).call
      expect(result.attendance_recorded).to be(true)
      expect(result.attendance_pay_cents).to eq(50_000) # 5 * (300_000 / 30)
      expect(result.net_pay_cents).to eq(50_000)
    end

    it "ignores attendance for owners (keeps full salary)" do
      salaried_owner = create(:user, :owner, company: company, monthly_salary_cents: 300_000)
      5.times do |i|
        StaffAttendance.create!(company: company, user: salaried_owner, recorded_by: owner,
                                attendance_status: present_status, date: payroll_month + i.days)
      end
      result = described_class.new(salaried_owner, payroll_month).call
      expect(result.attendance_recorded).to be(false)
      expect(result.net_pay_cents).to eq(300_000)
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
      expect(result.paid_cents).to eq(0)
      expect(result.remaining_pay_cents).to eq(290_000)
    end

    it "takes money already paid to them this month off what is still owed" do
      treasury = Treasury.create!(
        company: company,
        name: "Safe",
        treasury_type: "safe",
        opening_balance_cents: 500_000,
        balance_cents: 500_000
      )

      Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT,
        treasury: treasury,
        user: owner,
        amount_cents: 50_000,
        voucher_date: payroll_month.change(day: 15),
        party_type: "User",
        party_id: staff.id
      ).call

      result = described_class.new(staff, payroll_month).call

      expect(result.paid_cents).to eq(50_000)
      expect(result.balance_cents).to eq(-50_000)
      expect(result.remaining_pay_cents).to eq(250_000)
    end

    it "uses the balance as of the month's end, not later months' payments" do
      treasury = Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                                  opening_balance_cents: 2_000_000, balance_cents: 2_000_000)
      june = Date.new(2026, 6, 1)
      [[june.change(day: 10), 500_000], [Date.new(2026, 7, 5), 400_000]].each do |date, cents|
        Accounting::RecordVoucherService.new(direction: Voucher::PAYMENT, treasury: treasury, user: owner,
                                             amount_cents: cents, voucher_date: date,
                                             party_type: "User", party_id: staff.id).call
      end

      open_june = described_class.new(staff, june).call
      expect(open_june.balance_cents).to eq(-500_000)
      expect(open_june.debt_cents).to eq(500_000)
      expect(open_june.payout_cents).to eq(0)

      Accounting::FinalizePayrollService.new(staff, june, finalized_by: owner).call
      recorded_june = described_class.new(staff, june).call
      # 5,000 advance less June's 3,000 pay: 2,000 owed at the end of June,
      # whatever was paid in July.
      expect(recorded_june.debt_cents).to eq(200_000)
      expect(recorded_june.deduction_cents).to eq(300_000)
      expect(staff.staff_balance_cents).to eq(-600_000)
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

  describe ".for_all_staff" do
    it "includes only active staff" do
      active = create(:user, company: company, name: "Active Staff", monthly_salary_cents: 300_000)
      create(:user, company: company, name: "Former Staff", monthly_salary_cents: 300_000, active: false)

      rows = described_class.for_all_staff(payroll_month)

      expect(rows.map { |row| row.user.id }).to eq([active.id])
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
