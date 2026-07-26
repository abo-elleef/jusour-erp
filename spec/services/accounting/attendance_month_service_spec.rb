# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::AttendanceMonthService do
  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  # 300_000 cents / 30 = 10_000 daily rate — clean math.
  let(:staff)   { create(:user, company: company, monthly_salary_cents: 300_000) }

  before { AttendanceStatus.seed_defaults!(company) }

  def status(code) = company.attendance_statuses.find_by!(code: code)

  # Mark days `range` of `month` with the given status code.
  def mark(month, range, code)
    range.each do |day|
      StaffAttendance.create!(
        company: company, user: staff, recorded_by: owner,
        date: Date.new(month.year, month.month, day),
        attendance_status: status(code)
      )
    end
  end

  let(:april) { Date.new(2026, 4, 1) }   # 30 days
  let(:july)  { Date.new(2026, 7, 1) }   # 31 days
  let(:feb)   { Date.new(2026, 2, 1) }   # 28 days

  def call(month) = described_class.new(staff, month).call

  it "pays nothing when there are no records" do
    result = call(april)
    expect(result.marked_days).to eq(0)
    expect(result.payable_days).to eq(0)
    expect(result.base_pay_cents).to eq(0)
    expect(result.fully_paid_month).to be(false)
  end

  it "pays the full monthly salary for a fully-present 30-day month" do
    mark(april, 1..30, "present")
    result = call(april)
    expect(result.fully_paid_month).to be(true)
    expect(result.payable_days).to eq(30)
    expect(result.base_pay_cents).to eq(300_000)
  end

  it "builds pay up per day for a mid-month joiner (blanks aren't paid)" do
    mark(april, 16..30, "present") # 15 days, days 1-15 blank
    result = call(april)
    expect(result.fully_paid_month).to be(false)
    expect(result.payable_days).to eq(15)
    expect(result.base_pay_cents).to eq(150_000) # 15 * 10_000
  end

  it "pays O (planned off) but not A (excused absence)" do
    mark(april, 1..28, "present") # 28 paid
    mark(april, 29..29, "off")    # paid
    mark(april, 30..30, "excused") # unpaid, no penalty
    result = call(april)
    expect(result.fully_paid_month).to be(false)
    expect(result.payable_days).to eq(29)        # 28 P + 1 O
    expect(result.penalty_days).to eq(0)
    expect(result.base_pay_cents).to eq(290_000) # 29 * 10_000
  end

  it "makes each X cost two days (unpaid day + 1 penalty)" do
    mark(april, 1..9, "present")   # 9 paid
    mark(april, 10..10, "unexcused") # 1 X
    # 10 marked days total; days 11-30 blank
    result = call(april)
    expect(result.payable_days).to eq(9)
    expect(result.penalty_days).to eq(1)
    # (9 payable - 1 penalty) * 10_000 = 80_000  → X removed 2 days vs a P
    expect(result.base_pay_cents).to eq(80_000)
  end

  it "pays full salary for a fully-present 31-day month (31st is free under /30)" do
    mark(july, 1..31, "present")
    result = call(july)
    expect(result.fully_paid_month).to be(true)
    expect(result.base_pay_cents).to eq(300_000)
  end

  it "pays full salary for a fully-present 28-day February (no underpay)" do
    mark(feb, 1..28, "present")
    result = call(feb)
    expect(result.fully_paid_month).to be(true)
    expect(result.base_pay_cents).to eq(300_000)
  end

  it "pays half a day for H (half day)" do
    mark(april, 1..1, "half_day")
    result = call(april)
    expect(result.payable_days).to eq(0.5)
    expect(result.base_pay_cents).to eq(5_000) # 0.5 * 10_000
  end

  it "adds a bonus day for PP within a partial month" do
    mark(april, 1..10, "present")       # 10 paid
    mark(april, 11..11, "present_bonus") # paid day + 1 bonus
    result = call(april)
    expect(result.payable_days).to eq(11)  # PP still counts as a present day
    expect(result.bonus_days).to eq(1)
    # (11 payable + 1 bonus) * 10_000 = 120_000
    expect(result.base_pay_cents).to eq(120_000)
  end

  it "adds the PP bonus on top of a full month's salary" do
    mark(april, 1..29, "present")
    mark(april, 30..30, "present_bonus") # day 30 present + bonus
    result = call(april)
    expect(result.fully_paid_month).to be(true) # every day is a paid day
    expect(result.bonus_days).to eq(1)
    expect(result.base_pay_cents).to eq(310_000) # 300_000 + 1 * 10_000
  end
end
