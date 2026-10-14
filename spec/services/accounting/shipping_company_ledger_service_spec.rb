# frozen_string_literal: true

require "rails_helper"

# Mirrors customer_ar_ledger_service_spec — a shipping company's balance is
# an AR-shaped receivable (we're owed the cash they're holding for us), it's
# just raised by a dispatch rather than a credit sale.
RSpec.describe Accounting::ShippingCompanyLedgerService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:shipping_company) { create(:shipping_company, company: company, name: "Speedy Courier") }
  let(:cash) do
    Treasury.create!(name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  before { Current.company = company }

  def balanced?(entry)
    entry.lines.sum(&:debit_cents) == entry.lines.sum(&:credit_cents)
  end

  it "raises the shipping company's balance and posts DR their ledger / CR Sales Revenue" do
    described_class.new(shipping_company).charge!(amount_cents: 50_000, user: user, occurred_on: Date.current)

    expect(shipping_company.reload.balance_cents).to eq(50_000)
    expect(shipping_company.ar_treasury.treasury_type).to eq("shipping_company_ar")

    entry = JournalEntry.where(company: company).order(:created_at).last
    expect(balanced?(entry)).to be(true)
    dr_line = entry.lines.find { |l| l.debit_cents.positive? }
    cr_line = entry.lines.find { |l| l.credit_cents.positive? }
    expect(dr_line.debit_cents).to eq(50_000)
    expect(cr_line.account_code).to eq(4001) # Sales revenue
  end

  it "does not create a ledger treasury for a shipping company nobody has dispatched through" do
    expect(shipping_company.ar_treasury).to be_nil
    expect(shipping_company.balance_cents).to eq(0)
  end

  it "a voucher with the shipping company as its party reduces their balance and the ledger stays balanced" do
    described_class.new(shipping_company).charge!(amount_cents: 50_000, user: user, occurred_on: Date.current)

    Accounting::RecordVoucherService.new(
      direction: "receipt", treasury: cash, user: user, amount_cents: 30_000,
      party_type: "ShippingCompany", party_id: shipping_company.id
    ).call

    expect(shipping_company.reload.balance_cents).to eq(20_000)
    expect(cash.reload.balance_cents).to eq(30_000)

    entries = JournalEntry.where(company: company)
    expect(entries.count).to be >= 2
    expect(entries.all? { |e| balanced?(e) }).to be(true)
  end
end
