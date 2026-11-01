# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::LabourCostService do
  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2801) }
  let(:today) { Date.new(2026, 11, 15) }

  def staff(n) = create(:user, company: company, wages_account_code: 2810 + n)

  def pay!(user, month, cents)
    PayrollSnapshot.create!(company: company, user: user, finalized_by: owner, payroll_month: month,
                            finalized_at: Time.current, net_pay_cents: cents)
  end

  def sell!(date, cents)
    @seq = (@seq || 0) + 1
    JournalEntry.create!(company: company, created_by: owner, date: date, description: "Daily close",
                         entry_number: "JE-L-#{@seq}", lines_attributes: [
                           { account_code: 1001, account_name: "Cash", account_type: "asset", debit_cents: cents, credit_cents: 0 },
                           { account_code: 4001, account_name: "Sales", account_type: "revenue", debit_cents: 0, credit_cents: cents }
                         ])
  end

  def report(from: Date.new(2026, 7, 1), to: Date.new(2026, 11, 30))
    described_class.new(start_date: from, end_date: to, today: today).call
  end

  let!(:team) { [staff(1), staff(2), staff(3), staff(4)] }

  it "sets each month's finalized pay against that month's sales" do
    sell!(Date.new(2026, 8, 3), 600_000)
    sell!(Date.new(2026, 8, 20), 400_000)
    team.each { |user| pay!(user, Date.new(2026, 8, 1), 30_000) }

    august = report.months.find { |m| m.month == Date.new(2026, 8, 1) }

    expect([august.revenue_cents, august.cost_cents, august.headcount]).to eq([1_000_000, 120_000, 4])
    expect(august.percent).to eq(12.0)
    expect(august.cost_per_head_cents).to eq(30_000)
    expect(august.status).to eq(:complete)
  end

  it "keeps incomplete months out of the totals, and says why" do
    sell!(Date.new(2026, 8, 3), 1_000_000)
    team.each { |user| pay!(user, Date.new(2026, 8, 1), 25_000) }
    sell!(Date.new(2026, 9, 3), 900_000)
    pay!(team.first, Date.new(2026, 9, 1), 25_000)            # one of four finalized
    sell!(Date.new(2026, 10, 3), 800_000)                     # no payroll yet
    team.each { |user| pay!(user, Date.new(2026, 7, 1), 25_000) } # pay before any sales on the books
    sell!(Date.new(2026, 11, 3), 100_000)                     # this month

    result = report
    statuses = result.months.to_h { |m| [m.month.month, m.status] }

    expect(statuses).to eq(7 => :no_revenue, 8 => :complete, 9 => :partial, 10 => :not_finalized, 11 => :current)
    expect(result.months.reject { |m| m.status == :complete }.map(&:percent)).to all(be_nil)
    expect([result.revenue_cents, result.cost_cents]).to eq([1_000_000, 100_000])
    expect(result.percent).to eq(10.0)
  end

  it "skips past months with neither sales nor pay" do
    sell!(Date.new(2026, 9, 3), 500_000)
    team.each { |user| pay!(user, Date.new(2026, 9, 1), 10_000) }

    expect(report.months.map { |m| m.month.month }).to eq([9, 11])
  end
end
