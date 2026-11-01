# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::KpiScorecardService do
  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 3001) }
  let(:august) { Date.new(2026, 8, 1) }

  def post!(date, *lines)
    @seq = (@seq || 0) + 1
    JournalEntry.create!(company: company, created_by: owner, date: date, description: "Entry",
                         entry_number: "JE-K-#{@seq}",
                         lines_attributes: lines.map { |code, name, type, debit, credit|
                           { account_code: code, account_name: name, account_type: type, debit_cents: debit, credit_cents: credit }
                         })
  end

  def sale!(date, cents) = post!(date, [1001, "Cash", "asset", cents, 0], [4001, "Sales", "revenue", 0, cents])
  def purchase!(date, cents) = post!(date, [5100, "Purchases / Inventory", "expense", cents, 0], [1001, "Cash", "asset", 0, cents])
  def rent!(date, cents) = post!(date, [5015, "Rent", "expense", cents, 0], [1001, "Cash", "asset", 0, cents])
  def count!(date, cents) = InventorySnapshot.create!(company: company, snapshot_date: date, value_cents: cents)

  def month_of(date, end_month: august)
    described_class.new(end_month: end_month, today: Date.new(2026, 11, 15)).call.find { |m| m.month == date }
  end

  it "takes margins from the P&L's periodic cost of goods" do
    sale!(august + 4, 1_000_000)
    purchase!(august + 6, 500_000)
    rent!(august + 9, 100_000)
    count!(august, 200_000)
    count!(august.end_of_month, 300_000)

    m = month_of(august)

    expect(m.cogs_cents).to eq(400_000) # 200,000 + 500,000 − 300,000
    expect(m.gross_margin).to eq(60.0)
    expect(m.food_cost).to eq(40.0)
    expect(m.net_margin).to eq(50.0)
    expect(m.inventory_days).to be_within(0.01).of(300_000 * 31 / 400_000.0)
  end

  it "uses a count on the 1st of next month as the closing stock when the month has none of its own" do
    sale!(august + 4, 1_000_000)
    purchase!(august + 6, 500_000)
    count!(august, 200_000)
    count!(august.next_month, 250_000)

    expect(month_of(august).cogs_cents).to eq(450_000)
  end

  it "leaves stock-based KPIs blank without counts at both ends" do
    sale!(august + 4, 1_000_000)
    purchase!(august + 6, 500_000)
    count!(august, 200_000)

    m = month_of(august)

    expect([m.cogs_cents, m.gross_margin, m.net_margin, m.food_cost, m.inventory_days, m.cash_cycle]).to all(be_nil)
    expect(m.revenue_cents).to eq(1_000_000)
  end

  it "adds finalized labour to food cost for prime cost" do
    sale!(august + 4, 1_000_000)
    purchase!(august + 6, 300_000)
    count!(august, 0)
    count!(august.end_of_month, 0)
    PayrollSnapshot.create!(company: company, user: create(:user, company: company, wages_account_code: 3002),
                            finalized_by: owner, payroll_month: august, finalized_at: Time.current, net_pay_cents: 150_000)

    m = month_of(august)

    expect([m.food_cost, m.labour_percent, m.prime_cost]).to eq([30.0, 15.0, 45.0])
  end

  it "measures days to pay suppliers from the AP ledger at month end" do
    supplier = Supplier.create!(name: "Mill", lead_time_days: 1, company: company)
    purchase!(august + 6, 620_000)
    TreasuryTransaction.create!(treasury: supplier.ap_treasury, user: owner, amount_cents: 200_000, kind: "ap_invoice",
                                description: "Invoice", occurred_on: august + 6, balance_after_cents: 200_000)
    TreasuryTransaction.create!(treasury: supplier.ap_treasury, user: owner, amount_cents: 999_000, kind: "ap_invoice",
                                description: "Later invoice", occurred_on: august.next_month + 2, balance_after_cents: 0)

    expect(month_of(august).dpo).to eq(200_000 * 31 / 620_000.0)
  end

  it "counts days to collect as zero for a business that does not sell on credit" do
    company.update!(business_type: "restaurant")
    sale!(august + 4, 1_000_000)

    expect(month_of(august).dso).to eq(0.0)
  end

  it "returns six months ending on the chosen month" do
    months = described_class.new(end_month: august, today: Date.new(2026, 11, 15)).call.map(&:month)

    expect(months).to eq((0..5).map { |i| august << (5 - i) })
  end
end
