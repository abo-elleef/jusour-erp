# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::MonthlyPayrollService do
  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000, pin: "1234")
  end
  let(:payroll_month) { Date.current.beginning_of_month }

  before { Current.company = company }

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

      Accounting::FinalizePayrollService.new(staff, payroll_month, finalized_by: owner).call
      staff.update!(monthly_salary_cents: 500_000)

      result = described_class.new(staff, payroll_month).call

      expect(result.finalized).to be(true)
      expect(result.base_salary_cents).to eq(300_000)
      expect(result.net_pay_cents).to eq(290_000)
    end
  end
end
