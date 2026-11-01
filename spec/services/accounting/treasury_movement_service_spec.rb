# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::TreasuryMovementService do
  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 3301) }
  let(:october) { Date.new(2026, 10, 1) }

  def treasury(name, type = "safe", **attrs)
    Treasury.create!(name: name, treasury_type: type, balance_cents: 0, opening_balance_cents: 0, company: company, **attrs)
  end

  def move!(treasury, cents, on, kind: "adjustment")
    TreasuryTransaction.create!(treasury: treasury, user: owner, amount_cents: cents, kind: kind,
                                description: "Movement", occurred_on: on, balance_after_cents: 0)
  end

  def report(user: owner) = described_class.new(start_date: october, end_date: october.end_of_month, user: user).call

  it "rolls each treasury from its opening to its closing balance, with transfers kept apart" do
    safe = treasury("Main safe")
    drawer = treasury("Drawer 1", "cash_drawer")
    move!(safe, 50_000, october - 5)                 # before the period
    move!(drawer, 30_000, october + 2, kind: "income")
    move!(safe, -8_000, october + 3, kind: "expense")
    move!(drawer, -20_000, october + 4, kind: "transfer")
    move!(safe, 20_000, october + 4, kind: "transfer")
    move!(safe, 99_000, october.next_month + 1)     # after the period

    result = report
    safe_row = result.rows.find { |row| row.treasury == safe }

    expect([safe_row.opening_cents, safe_row.in_cents, safe_row.out_cents, safe_row.transfer_cents, safe_row.closing_cents])
      .to eq([50_000, 0, 8_000, 20_000, 62_000])
    expect([result.in_cents, result.out_cents, result.transfer_cents]).to eq([30_000, 8_000, 0])
    expect(result.closing_cents).to eq(72_000)
    expect(result.kinds.map { |k| [k.kind, k.in_cents, k.out_cents] }).to contain_exactly(["income", 30_000, 0], ["expense", 0, 8_000])
  end

  it "leaves out the supplier and customer ledgers, idle treasuries, and restricted ones a user may not see" do
    supplier = Supplier.create!(name: "Mill", lead_time_days: 1, company: company)
    move!(supplier.ap_treasury, 5_000, october + 1, kind: "ap_invoice")
    treasury("Idle safe")
    secret = treasury("Owner's safe", restricted: true)
    move!(secret, 1_000, october + 1)

    expect(report.rows.map { |row| row.treasury.name }).to eq(["Owner's safe"])
    expect(report(user: create(:user, company: company, wages_account_code: 3302)).rows).to be_empty
  end
end
