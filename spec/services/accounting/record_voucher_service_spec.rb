# frozen_string_literal: true

require "rails_helper"

# A voucher is the cash half of an income or an expense, carrying its own date.
# The point of the split: the expense belongs to the month it was incurred, the
# cash to the month it left, and 2300 holds the difference in between.
RSpec.describe Accounting::RecordVoucherService do
  let(:company) { create(:company) }
  let(:user)    { create(:user, company: company) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end

  before { Current.company = company }

  def balanced?(entry)
    entry.lines.sum(&:debit_cents) == entry.lines.sum(&:credit_cents)
  end

  def latest_entry
    JournalEntry.where(company: company).order(:created_at).last
  end

  describe "a payment voucher (سند صرف)" do
    it "takes the cash out and clears the accrued payable" do
      voucher = described_class.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user,
        amount_cents: 25_000, voucher_date: Date.current
      ).call

      expect(cash.reload.balance_cents).to eq(75_000)

      entry = latest_entry
      expect(balanced?(entry)).to be(true)
      debit = entry.lines.find { |l| l.debit_cents.positive? }
      credit = entry.lines.find { |l| l.credit_cents.positive? }
      expect(debit.account_code).to eq(Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE)
      expect(credit.treasury_id).to eq(cash.id)
    end

    it "records the cash movement against the treasury as its own kind" do
      voucher = described_class.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 25_000
      ).call

      txn = TreasuryTransaction.find_by(source_record: voucher)
      expect(txn.kind).to eq("voucher_payment")
      expect(txn.amount_cents).to eq(-25_000)
      expect(txn.occurred_on).to eq(voucher.voucher_date)
    end
  end

  describe "a receipt voucher (سند قبض)" do
    it "brings the cash in and clears the receivable" do
      described_class.new(
        direction: Voucher::RECEIPT, treasury: cash, user: user, amount_cents: 40_000
      ).call

      expect(cash.reload.balance_cents).to eq(140_000)

      entry = latest_entry
      expect(balanced?(entry)).to be(true)
      debit = entry.lines.find { |l| l.debit_cents.positive? }
      credit = entry.lines.find { |l| l.credit_cents.positive? }
      expect(debit.treasury_id).to eq(cash.id)
      expect(credit.account_code).to eq(Accounting::JournalEntryService::OTHER_RECEIVABLES_CODE)
    end
  end

  describe "the date split, which is the whole point" do
    it "leaves the cash on the voucher's date, not the expense's" do
      voucher = described_class.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user,
        amount_cents: 10_000, voucher_date: Date.new(2026, 10, 5)
      ).call

      expect(latest_entry.date).to eq(Date.new(2026, 10, 5))
      expect(TreasuryTransaction.find_by(source_record: voucher).occurred_on)
        .to eq(Date.new(2026, 10, 5))
    end
  end

  describe "numbering" do
    it "runs separate books for receipts and payments, each resetting yearly" do
      first_payment = described_class.new(direction: Voucher::PAYMENT, treasury: cash,
                                          user: user, amount_cents: 1_000).call
      first_receipt = described_class.new(direction: Voucher::RECEIPT, treasury: cash,
                                          user: user, amount_cents: 1_000).call
      second_payment = described_class.new(direction: Voucher::PAYMENT, treasury: cash,
                                           user: user, amount_cents: 1_000).call

      year = Date.current.year
      expect(first_payment.number).to eq("PV-#{year}-00001")
      expect(first_receipt.number).to eq("RV-#{year}-00001")
      expect(second_payment.number).to eq("PV-#{year}-00002")
    end
  end

  describe "allocations" do
    let(:category) do
      ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
    end
    # On account: no treasury, so nothing has been paid and the whole 30,000 is
    # sitting on 2300 waiting for a voucher.
    let(:expense) do
      Expense.create!(expense_category: category, user: user,
                      description: "September rent", amount_cents: 30_000,
                      expense_date: Date.new(2026, 9, 1), company: company)
    end

    it "records what the voucher settled and for how much" do
      voucher = described_class.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 30_000,
        voucher_date: Date.new(2026, 10, 5),
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call

      allocation = voucher.payment_allocations.sole
      expect(allocation.settles).to eq(expense)
      expect(allocation.amount_cents).to eq(30_000)
      expect(voucher.unallocated_cents).to eq(0)
    end

    it "leaves a part-payment readable on both sides" do
      voucher = described_class.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 10_000,
        allocations: [{ settles: expense, amount_cents: 10_000 }]
      ).call

      expect(voucher.unallocated_cents).to eq(0)
      expect(expense.payment_allocations.sum(:amount_cents)).to eq(10_000)
    end

    it "keeps money paid on account unallocated rather than inventing a target" do
      voucher = described_class.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 50_000,
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call

      expect(voucher.unallocated_cents).to eq(20_000)
    end

    it "refuses to settle more than the voucher is worth" do
      expect {
        described_class.new(
          direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 10_000,
          allocations: [{ settles: expense, amount_cents: 30_000 }]
        ).call
      }.to raise_error(described_class::Error)
    end
  end

  describe "validation" do
    it "refuses a non-positive amount" do
      expect {
        described_class.new(direction: Voucher::PAYMENT, treasury: cash,
                            user: user, amount_cents: 0).call
      }.to raise_error(described_class::Error)
    end

    it "refuses an unknown direction" do
      expect {
        described_class.new(direction: "transfer", treasury: cash,
                            user: user, amount_cents: 1_000).call
      }.to raise_error(described_class::Error)
    end

    it "writes nothing at all when it refuses" do
      expect {
        begin
          described_class.new(direction: Voucher::PAYMENT, treasury: cash,
                              user: user, amount_cents: 0).call
        rescue described_class::Error
          nil
        end
      }.not_to change { [Voucher.count, TreasuryTransaction.count, JournalEntry.count] }
    end
  end
end
