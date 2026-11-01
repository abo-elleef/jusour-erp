# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::TrialBalanceService do
  let(:company) { Current.company }
  let(:user) { create(:user, :owner, company: company, wages_account_code: 2601) }
  let(:cash) do
    Treasury.create!(name: "Main safe", treasury_type: "safe", balance_cents: 0, opening_balance_cents: 0, company: company)
  end
  let(:supplier) { Supplier.create!(name: "Mill", lead_time_days: 1, company: company) }

  # lines: [[account, debit, credit, treasury?]] — account is [code, name, type]
  def post!(date, *lines, description: "Entry")
    @seq = (@seq || 0) + 1
    JournalEntry.create!(company: company, created_by: user, date: date, description: description,
                         entry_number: "JE-T-#{@seq.to_s.rjust(4, '0')}",
                         lines_attributes: lines.map { |(code, name, type), debit, credit, treasury|
                           { account_code: code, account_name: name, account_type: type,
                             debit_cents: debit, credit_cents: credit, treasury_id: treasury&.id }
                         })
  end

  def move!(treasury, cents, date)
    TreasuryTransaction.create!(treasury: treasury, user: user, amount_cents: cents, kind: "adjustment",
                                description: "Movement", occurred_on: date, balance_after_cents: 0)
  end

  let(:sales) { [4001, "Sales", "revenue"] }
  let(:rent) { [5005, "Rent", "expense"] }
  let(:cash_account) { [cash.to_account.code, cash.name, "asset"] }

  let(:start_date) { Date.new(2026, 10, 1) }
  let(:end_date) { Date.new(2026, 10, 31) }

  def result(**opts) = Accounting::TrialBalanceService.new(start_date: start_date, end_date: end_date, **opts).call
  def row_for(result, name) = result.rows.find { |row| row.account.name == name }

  it "splits each account into opening, period debits and credits, and closing — and balances" do
    post!(Date.new(2026, 9, 20), [cash_account, 50_000, 0, cash], [sales, 0, 50_000])
    post!(Date.new(2026, 10, 5), [cash_account, 30_000, 0, cash], [sales, 0, 30_000])
    post!(Date.new(2026, 10, 9), [rent, 12_000, 0], [cash_account, 0, 12_000, cash])
    post!(Date.new(2026, 11, 2), [cash_account, 99_000, 0, cash], [sales, 0, 99_000]) # after the period

    tb = result
    safe = row_for(tb, "Main safe")

    expect([safe.opening_cents, safe.debit_cents, safe.credit_cents, safe.closing_cents]).to eq([50_000, 30_000, 12_000, 68_000])
    expect(row_for(tb, "Sales").closing_cents).to eq(-80_000)
    expect(row_for(tb, "Rent").closing_cents).to eq(12_000)
    expect(tb).to be_balanced
    expect(tb.debit_cents).to eq(42_000)
    expect(tb.groups.map(&:first)).to eq(%w[asset revenue expense])
  end

  it "keeps a treasury's lines together under its current code, even when posted under older codes" do
    ap = supplier.ap_treasury
    old_code = ap.to_account.code + 500
    post!(Date.new(2026, 10, 2), [[5100, "Purchases", "expense"], 10_000, 0], [[old_code, "Mill — AP", "liability"], 0, 10_000, ap])
    post!(Date.new(2026, 10, 3), [[5100, "Purchases", "expense"], 5_000, 0], [[ap.to_account.code, "Mill — AP", "liability"], 0, 5_000, ap])

    row = row_for(result, ap.name)

    expect(row.account.code).to eq(ap.to_account.code)
    expect(row.credit_cents).to eq(15_000)
    expect(result.rows.count { |r| r.account.treasury == ap }).to eq(1)
  end

  it "keeps two treasuries apart even when their lines share a code" do
    other = Treasury.create!(name: "Second safe", treasury_type: "safe", balance_cents: 0, opening_balance_cents: 0, company: company)
    post!(Date.new(2026, 10, 2), [[1999, "Safe", "asset"], 1_000, 0, cash], [sales, 0, 1_000])
    post!(Date.new(2026, 10, 2), [[1999, "Safe", "asset"], 2_000, 0, other], [sales, 0, 2_000])

    expect(row_for(result, "Main safe").debit_cents).to eq(1_000)
    expect(row_for(result, "Second safe").debit_cents).to eq(2_000)
  end

  it "flags a treasury whose own balance disagrees with the journal, and one that never reached it" do
    post!(Date.new(2026, 10, 5), [cash_account, 30_000, 0, cash], [sales, 0, 30_000])
    move!(cash, 30_000, Date.new(2026, 10, 5))
    move!(cash, -4_000, Date.new(2026, 10, 6)) # paid out with no journal entry
    silent = Treasury.create!(name: "Petty cash", treasury_type: "petty_cash", balance_cents: 0, opening_balance_cents: 0, company: company)
    move!(silent, 700, Date.new(2026, 10, 7))

    tb = result

    expect(row_for(tb, "Main safe").treasury_difference_cents).to eq(4_000)
    expect(row_for(tb, "Petty cash").treasury_difference_cents).to eq(-700)
    expect(row_for(tb, "Sales").treasury_difference_cents).to be_nil
    expect(tb.difference_count).to eq(2)
    filtered = result(differences_only: true)
    expect(filtered.rows.map { |r| r.account.name }).to contain_exactly("Main safe", "Petty cash")
    expect(filtered.summary).to be_balanced # judged on every account, not the filtered few
    expect(filtered.summary.rows.size).to eq(3)
  end

  it "reads a supplier's difference in the direction of what we owe" do
    ap = supplier.ap_treasury
    post!(Date.new(2026, 10, 2), [[5100, "Purchases", "expense"], 10_000, 0], [[ap.to_account.code, "Mill — AP", "liability"], 0, 10_000, ap])
    move!(ap, 6_000, Date.new(2026, 10, 2))

    expect(row_for(result, ap.name).treasury_difference_cents).to eq(4_000) # journal says we owe 4,000 more
  end

  it "uses an account's latest name when a category was renamed" do
    post!(Date.new(2026, 9, 1), [[5009, "Transport", "expense"], 100, 0], [cash_account, 0, 100, cash])
    post!(Date.new(2026, 10, 1), [[5009, "Transport & delivery", "expense"], 100, 0], [cash_account, 0, 100, cash])

    names = result.rows.map { |r| r.account.name }
    expect(names).to include("Transport & delivery")
    expect(names).not_to include("Transport")
  end

  describe Accounting::GeneralLedgerService do
    it "lists the period's lines with a running balance that starts from the opening" do
      post!(Date.new(2026, 9, 20), [cash_account, 50_000, 0, cash], [sales, 0, 50_000])
      post!(Date.new(2026, 10, 5), [cash_account, 30_000, 0, cash], [sales, 0, 30_000], description: "Sale")
      post!(Date.new(2026, 10, 9), [rent, 12_000, 0], [cash_account, 0, 12_000, cash], description: "Rent paid")

      account = row_for(result, "Main safe").account
      ledger = described_class.new(account: account, start_date: start_date, end_date: end_date)

      expect(ledger.opening_cents).to eq(50_000)
      expect(ledger.lines.map { |line| [line.entry_description, line.balance_cents.to_i] })
        .to eq([["Sale", 80_000], ["Rent paid", 68_000]])
      expect([ledger.debit_cents, ledger.credit_cents, ledger.closing_cents]).to eq([30_000, 12_000, 68_000])
      expect(Accounting::TrialBalanceService.account_for(account.key).name).to eq("Main safe")
    end
  end
end
