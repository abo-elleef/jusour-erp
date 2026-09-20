# frozen_string_literal: true

require "rails_helper"

# Adjusting a treasury moves real money — 1.7m across this company's history —
# and used to leave no document at all: no number, no counterparty, and a
# journal entry with `source: nil`, so nothing could be traced back to why a
# balance changed. It also dated the entry today while dating the cash movement
# `occurred_on`, so a back-dated adjustment landed in two different months.
RSpec.describe "Adjusting a treasury" do
  let(:company) { Current.company }
  let(:user)    { create(:user) }
  let(:safe) do
    Treasury.create!(name: "Safe", treasury_type: "safe", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end

  def adjust!(amount_cents, occurred_on: Date.current, description: "Found cash")
    Accounting::TreasuryLedgerService.new.record_adjustment!(
      treasury: safe, user: user, amount_cents: amount_cents,
      description: description, occurred_on: occurred_on
    )
  end

  def entry_for(voucher) = JournalEntry.for_source(voucher).sole

  describe "money put in" do
    it "issues a numbered receipt voucher" do
      voucher = adjust!(25_000)

      expect(voucher).to be_a(Voucher)
      expect(voucher).to be_receipt
      expect(voucher).to be_equity_adjustment
      expect(voucher.number).to start_with("RV-")
      expect(voucher.amount_cents).to eq(25_000)
      expect(safe.reload.balance_cents).to eq(125_000)
    end

    it "posts it against equity, as adjusting a balance always did" do
      voucher = adjust!(25_000)

      entry = entry_for(voucher)
      expect(entry.lines.sum(&:debit_cents)).to eq(entry.lines.sum(&:credit_cents))

      debit  = entry.lines.find { |l| l.debit_cents.positive? }
      credit = entry.lines.find { |l| l.credit_cents.positive? }
      expect(debit.treasury_id).to eq(safe.id)
      expect(credit.account_code).to eq(Accounting::JournalEntryService::EQUITY_CODE)
    end
  end

  describe "money taken out" do
    it "issues a payment voucher and takes the cash" do
      voucher = adjust!(-25_000)

      expect(voucher).to be_payment
      expect(voucher.number).to start_with("PV-")
      expect(voucher.amount_cents).to eq(25_000)
      expect(safe.reload.balance_cents).to eq(75_000)

      entry = entry_for(voucher)
      debit = entry.lines.find { |l| l.debit_cents.positive? }
      expect(debit.account_code).to eq(Accounting::JournalEntryService::EQUITY_CODE)
    end
  end

  describe "what the reports read" do
    it "keeps the adjustment treasury kind, so the cash flow still sees it" do
      voucher = adjust!(25_000)

      txn = TreasuryTransaction.find_by(source_record: voucher)
      expect(txn.kind).to eq("adjustment")
      expect(Accounting::CashFlowService::OPERATING_KINDS).to include("adjustment")
    end

    it "still shows up as an equity adjustment on the profit-to-cash bridge" do
      adjust!(25_000)

      bridge = Accounting::ProfitVsCashService.new(
        start_date: Date.current.beginning_of_month, end_date: Date.current.end_of_month
      )
      line = bridge.lines.find { |l| l.key == :equity_adjustments }
      expect(line.amount_cents).to eq(25_000)
      expect(bridge.residual_cents).to eq(0)
    end
  end

  describe "a back-dated adjustment" do
    it "puts the cash and the entry on the same day" do
      voucher = adjust!(25_000, occurred_on: Date.new(2026, 7, 1))

      expect(voucher.voucher_date).to eq(Date.new(2026, 7, 1))
      expect(entry_for(voucher).date).to eq(Date.new(2026, 7, 1))
      expect(TreasuryTransaction.find_by(source_record: voucher).occurred_on)
        .to eq(Date.new(2026, 7, 1))
    end
  end

  describe "traceability, which is the point" do
    it "links the entry back to the voucher that caused it" do
      voucher = adjust!(25_000, description: "Cash found in the old safe")

      entry = entry_for(voucher)
      expect(entry.source_record).to eq(voucher)
      expect(voucher.notes).to eq("Cash found in the old safe")
    end

    it "can be voided, giving the money back" do
      voucher = adjust!(25_000)
      expect(safe.reload.balance_cents).to eq(125_000)

      voucher.destroy!

      expect(safe.reload.balance_cents).to eq(100_000)
      expect(JournalEntry.where(source_record_type: "Voucher", source_record_id: voucher.id)).to be_empty
    end
  end
end
