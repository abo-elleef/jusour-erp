# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::StaffStatementService do
  let(:company) { create(:company) }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:staff)   { create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000) }
  let(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
                     opening_balance_cents: 1_000_000, balance_cents: 1_000_000)
  end

  before do
    Current.company = company
    pay(Voucher::PAYMENT, 100_000, Date.new(2026, 6, 10))
    pay(Voucher::PAYMENT, 50_000, Date.new(2026, 7, 5))
    pay(Voucher::RECEIPT, 20_000, Date.new(2026, 8, 1))
  end

  def pay(direction, cents, date)
    Accounting::RecordVoucherService.new(direction: direction, treasury: safe, user: owner, amount_cents: cents,
                                         voucher_date: date, party_type: "User", party_id: staff.id).call
  end

  it "lists oldest first, as a statement reads, with the running balance over the whole account" do
    lines = described_class.new(staff).lines.to_a
    expect(lines.map(&:running_balance_cents)).to eq([-100_000, -150_000, -130_000])
  end

  it "keeps each row's running balance when a date range hides earlier rows" do
    statement = described_class.new(staff, from: Date.new(2026, 7, 1), to: Date.new(2026, 7, 31))

    expect(statement.lines.map(&:running_balance_cents)).to eq([-150_000])
    expect(statement.opening_balance_cents).to eq(-100_000)
    expect(statement.closing_balance_cents).to eq(-150_000)
    expect(statement.range_debit_cents).to eq(50_000)
    expect(statement.range_credit_cents).to eq(0)
  end
end
