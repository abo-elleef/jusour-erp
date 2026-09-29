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
    expect(adjustment.amount_cents).to eq(7_500) # 5 hours * 1_000 * 1.5x overtime rate
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

  it "scopes attendance late notes in both locales" do
    late = described_class.create!(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "quarter_day",
      payroll_month: Date.current.beginning_of_month,
      notes: I18n.t("accounting.attendance.late_note", locale: :en)
    )
    staff_page = described_class.create!(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "quarter_day",
      payroll_month: Date.current.beginning_of_month,
      notes: "Other"
    )

    expect(described_class.attendance_late).to contain_exactly(late)
    expect(described_class.attendance_late).not_to include(staff_page)
  end

  it "exposes day units for quarter, half, and full penalties" do
    expect(described_class.new(unit_type: "quarter_day").day_units).to eq(0.25)
    expect(described_class.new(unit_type: "half_day").day_units).to eq(0.5)
    expect(described_class.new(unit_type: "full_day").day_units).to eq(1)
  end

  it "refuses a new adjustment once the month's payroll is finalized" do
    month = Date.current.beginning_of_month
    treasury = Treasury.create!(name: "Payroll Safe", treasury_type: "safe",
      opening_balance_cents: 1_000_000, balance_cents: 1_000_000)

    PayrollSnapshot.create!(
      user: staff, payroll_month: month, finalized_by: owner, treasury: treasury,
      base_salary_cents: 300_000, daily_rate_cents: 0, penalties_cents: 0, bonuses_cents: 0,
      advances_cents: 0, net_pay_cents: 300_000, remaining_pay_cents: 300_000,
      finalized_at: Time.current, paid_on: month.end_of_month
    )

    adjustment = described_class.new(
      user: staff, recorded_by: owner, kind: "bonus", unit_type: "fixed",
      amount_cents: 5_000, payroll_month: month
    )

    expect(adjustment).not_to be_valid
    expect(adjustment.errors[:base]).to include(I18n.t("activerecord.errors.models.payroll_adjustment.attributes.base.payroll_finalized"))
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
