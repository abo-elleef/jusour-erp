# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sales::LegacyOpeningBalanceImporter do
  let(:company) { create(:company) }
  let!(:owner) { create(:user, company: company, role: "owner") }
  let!(:customer) { create(:customer, company: company, name: "شركة الفيروز", legacy_code: "7") }

  before { Current.company = company }

  def row(overrides = {})
    {
      "customer_code" => "7", "customer_name" => "شركة الفيروز",
      "balance_cents" => "865000", "reported_balance_cents" => "865000",
      "last_transaction_date" => "2025-10-14"
    }.merge(overrides)
  end

  def import(rows, **options)
    described_class.new(rows: rows, company: company, dry_run: false, **options).call
  end

  it "posts the balance as an AR opening-balance ledger entry" do
    result = import([row])

    expect(result.posted).to eq(1)
    customer.reload
    expect(customer.ar_balance_cents).to eq(865_000)
    expect(JournalEntry.count).to eq(1)
  end

  it "dates the entry from the statement's last transaction" do
    import([row], dry_run: false)

    expect(TreasuryTransaction.last.occurred_on).to eq(Date.new(2025, 10, 14))
  end

  it "skips a zero balance" do
    result = import([row("balance_cents" => "0")])

    expect(result.skipped_zero).to eq(1)
    expect(result.posted).to eq(0)
    expect(customer.reload.ar_balance_cents).to eq(0)
  end

  it "skips a negative (credit) balance rather than guessing how to post it" do
    result = import([row("balance_cents" => "-750000")])

    expect(result.posted).to eq(0)
    expect(result.skipped_credit.size).to eq(1)
    expect(result.skipped_credit.first).to include("-7500.0")
  end

  it "skips a customer who already carries an AR balance" do
    import([row])
    result = import([row])

    expect(result.skipped_existing).to eq(1)
    expect(result.posted).to eq(0)
  end

  it "records a customer it can't find rather than raising" do
    result = import([row("customer_code" => "999", "customer_name" => "Ghost")])

    expect(result.customer_not_found).to eq(["999 Ghost"])
    expect(result.posted).to eq(0)
  end

  it "flags a mismatch against the sheet's own current-balance figure without blocking the post" do
    result = import([row("balance_cents" => "865000", "reported_balance_cents" => "500000")])

    expect(result.posted).to eq(1)
    expect(result.mismatches.size).to eq(1)
    expect(result.mismatches.first).to include("8650.0").and include("5000.0")
  end

  it "does not write anything in dry-run mode" do
    result = described_class.new(rows: [row], company: company, dry_run: true).call

    expect(result.posted).to eq(1)
    expect(customer.reload.ar_balance_cents).to eq(0)
    expect(JournalEntry.count).to eq(0)
  end
end
