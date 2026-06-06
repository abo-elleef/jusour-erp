# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayrollAdjustment, type: :model do
  let(:owner) do
    User.create!(
      name: "Owner",
      email: "payroll-owner@example.com",
      role: "owner",
      password: "password123",
      monthly_salary_cents: 600_000
    )
  end

  let(:staff) do
    User.create!(
      name: "Staff",
      email: "payroll-staff@example.com",
      role: "cashier",
      password: "password123",
      monthly_salary_cents: 300_000
    )
  end

  it "computes full-day penalty from monthly salary over 30 days" do
    adjustment = described_class.create!(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "full_day",
      payroll_month: Date.current.beginning_of_month
    )

    expect(adjustment.amount_cents).to eq(10_000)
  end

  it "computes half-day bonus" do
    adjustment = described_class.create!(
      user: staff,
      recorded_by: owner,
      kind: "bonus",
      unit_type: "half_day",
      payroll_month: Date.current.beginning_of_month
    )

    expect(adjustment.amount_cents).to eq(5_000)
  end

  it "uses fixed amount when unit type is fixed" do
    adjustment = described_class.create!(
      user: staff,
      recorded_by: owner,
      kind: "bonus",
      unit_type: "fixed",
      amount_cents: 7_500,
      payroll_month: Date.current.beginning_of_month
    )

    expect(adjustment.amount_cents).to eq(7_500)
  end

  it "computes overtime bonus from hours and hourly rate" do
    adjustment = described_class.create!(
      user: staff,
      recorded_by: owner,
      kind: "bonus",
      unit_type: "overtime",
      overtime_hours: 5,
      payroll_month: Date.current.beginning_of_month
    )

    expect(staff.hourly_rate_cents).to eq(1_000)
    expect(adjustment.amount_cents).to eq(5_000)
    expect(adjustment.unit_label).to include("5")
  end

  it "rejects overtime on penalties" do
    adjustment = described_class.new(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "overtime",
      overtime_hours: 2,
      payroll_month: Date.current.beginning_of_month
    )

    expect(adjustment).not_to be_valid
  end
end

RSpec.describe Accounting::MonthlyPayrollService do
  let(:staff) do
    User.create!(
      name: "Staff",
      email: "payroll-service@example.com",
      role: "cashier",
      password: "password123",
      monthly_salary_cents: 300_000
    )
  end

  let(:owner) do
    User.create!(
      name: "Owner",
      email: "payroll-service-owner@example.com",
      role: "owner",
      password: "password123"
    )
  end

  it "calculates net pay with penalties and bonuses" do
    month = Date.current.beginning_of_month

    PayrollAdjustment.create!(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "full_day",
      payroll_month: month
    )

    PayrollAdjustment.create!(
      user: staff,
      recorded_by: owner,
      kind: "bonus",
      unit_type: "fixed",
      amount_cents: 5_000,
      payroll_month: month
    )

    result = described_class.new(staff, month).call

    expect(result.base_salary_cents).to eq(300_000)
    expect(result.penalties_cents).to eq(10_000)
    expect(result.bonuses_cents).to eq(5_000)
    expect(result.net_pay_cents).to eq(295_000)
  end
end

RSpec.describe User do
  it "derives daily rate from monthly salary using 30 work days" do
    user = described_class.new(monthly_salary_cents: 300_000)
    expect(user.daily_rate_cents).to eq(10_000)
  end

  it "derives hourly rate from monthly salary over 300 work hours" do
    user = described_class.new(monthly_salary_cents: 300_000)
    user.valid?
    expect(user.hourly_rate_cents).to eq(1_000)
  end
end
