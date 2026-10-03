# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::FinalizePayrollService do
  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:staff) do
    create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000, pin: "1234")
  end
  let(:payroll_month) { Date.current.beginning_of_month }
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Safe",
      treasury_type: "safe",
      opening_balance_cents: 500_000,
      balance_cents: 500_000
    )
  end

  before { Current.company = company }

  it "floors a negative net/remaining pay at zero instead of raising" do
    PayrollAdjustment.create!(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "fixed",
      amount_cents: 350_000,
      payroll_month: payroll_month,
      happened_at: payroll_month
    )

    snapshot = described_class.new(
      staff,
      payroll_month,
      finalized_by: owner,
      treasury: treasury,
      paid_on: payroll_month.end_of_month
    ).call

    expect(snapshot).to be_persisted
    expect(snapshot.net_pay_cents).to eq(0)
    expect(snapshot.remaining_pay_cents).to eq(0)
    expect(snapshot.treasury).to be_nil
    expect(snapshot.paid_on).to be_nil
  end

  it "does not post a treasury payout when the floored remaining pay is zero" do
    PayrollAdjustment.create!(
      user: staff,
      recorded_by: owner,
      kind: "penalty",
      unit_type: "fixed",
      amount_cents: 350_000,
      payroll_month: payroll_month,
      happened_at: payroll_month
    )

    snapshot = described_class.new(
      staff,
      payroll_month,
      finalized_by: owner,
      treasury: treasury,
      paid_on: payroll_month.end_of_month
    ).call

    expect(snapshot.treasury_transactions).to be_empty
    expect(treasury.reload.balance_cents).to eq(500_000)
  end

  it "keeps recording a normal, positive payroll" do
    snapshot = described_class.new(
      staff,
      payroll_month,
      finalized_by: owner,
      treasury: treasury,
      paid_on: payroll_month.end_of_month
    ).call

    expect(snapshot.net_pay_cents).to eq(300_000)
    expect(snapshot.remaining_pay_cents).to eq(300_000)
    expect(snapshot.treasury).to eq(treasury)
  end
end
