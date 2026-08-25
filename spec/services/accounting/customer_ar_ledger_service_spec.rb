# frozen_string_literal: true

require "rails_helper"

# SPIKE proof: Accounts-Receivable credit sales post correctly to the real
# double-entry ledger and track a per-customer balance, mirroring supplier AP.
RSpec.describe Accounting::CustomerArLedgerService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:customer) { create(:customer, company: company, name: "Bazzar Clinic") }
  let(:cash) do
    Treasury.create!(name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  before { Current.company = company }

  def balanced?(entry)
    entry.lines.sum(&:debit_cents) == entry.lines.sum(&:credit_cents)
  end

  it "raises a receivable and posts DR Accounts Receivable / CR Sales Revenue" do
    described_class.new(customer).charge!(amount_cents: 100_000, user: user, occurred_on: Date.current)

    # Per-customer balance = amount owed.
    expect(customer.reload.ar_balance_cents).to eq(100_000)
    expect(customer.ar_treasury.treasury_type).to eq("customer_ar")

    entry = JournalEntry.where(company: company).order(:created_at).last
    expect(balanced?(entry)).to be(true)

    ar_line = entry.lines.find { |l| l.debit_cents.positive? }
    rev_line = entry.lines.find { |l| l.credit_cents.positive? }
    expect(ar_line.account_type).to eq("asset")        # Accounts Receivable
    expect(ar_line.debit_cents).to eq(100_000)
    expect(rev_line.account_code).to eq(4001)          # Sales revenue
    expect(rev_line.account_type).to eq("revenue")
    expect(rev_line.credit_cents).to eq(100_000)
  end

  it "settles across multiple payments over time and posts DR cash / CR AR each time" do
    svc = described_class.new(customer)
    svc.charge!(amount_cents: 100_000, user: user, occurred_on: 60.days.ago.to_date)

    svc.settle!(treasury: cash, amount_cents: 40_000, user: user, occurred_on: 30.days.ago.to_date)
    expect(customer.reload.ar_balance_cents).to eq(60_000)
    expect(cash.reload.balance_cents).to eq(40_000) # money came into the drawer

    receipt = JournalEntry.where(company: company).order(:created_at).last
    expect(balanced?(receipt)).to be(true)
    dr = receipt.lines.find { |l| l.debit_cents.positive? }
    cr = receipt.lines.find { |l| l.credit_cents.positive? }
    expect(dr.treasury_id).to eq(cash.id)                 # DR cash drawer
    expect(cr.treasury_id).to eq(customer.ar_treasury.id) # CR Accounts Receivable

    svc.settle!(treasury: cash, amount_cents: 60_000, user: user, occurred_on: Date.current)
    expect(customer.reload.ar_balance_cents).to eq(0)     # fully paid off
    expect(cash.reload.balance_cents).to eq(100_000)
  end

  it "splits revenue and tax on the credit sale" do
    described_class.new(customer).charge!(amount_cents: 113_000, revenue_cents: 100_000,
      tax_cents: 13_000, user: user, occurred_on: Date.current)

    entry = JournalEntry.where(company: company).order(:created_at).last
    expect(balanced?(entry)).to be(true)
    expect(entry.lines.find { |l| l.account_code == 4001 }.credit_cents).to eq(100_000)
    expect(entry.lines.find { |l| l.account_code == 2100 }.credit_cents).to eq(13_000)
    expect(customer.reload.ar_balance_cents).to eq(113_000)
  end

  it "every generated journal entry balances (double-entry holds)" do
    svc = described_class.new(customer)
    svc.charge!(amount_cents: 50_000, user: user, occurred_on: Date.current)
    svc.settle!(treasury: cash, amount_cents: 20_000, user: user, occurred_on: Date.current)

    entries = JournalEntry.where(company: company)
    expect(entries.count).to be >= 2
    expect(entries.all? { |e| balanced?(e) }).to be(true)
  end

  it "does not create an AR ledger for customers who never buy on credit" do
    plain = create(:customer, company: company, name: "Walk-in")
    expect(plain.ar_treasury).to be_nil
    expect(plain.ar_balance_cents).to eq(0)
  end
end
