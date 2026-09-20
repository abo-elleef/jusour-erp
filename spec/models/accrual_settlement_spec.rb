# frozen_string_literal: true

require "rails_helper"

# The requirement this whole change exists for: an expense belongs to the month
# it was incurred, the cash to the month it left, and an accrued payable holds
# the difference in between.
RSpec.describe "Accrual and settlement" do
  let(:company) { create(:company) }
  let(:user)    { create(:user, company: company) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end
  let(:category) do
    ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
  end
  let(:income_category) do
    IncomeCategory.create!(name: "Catering", category_type: "catering", position: 1, company: company)
  end

  before { Current.company = company }

  ACCRUED = Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE
  RECEIVABLE = Accounting::JournalEntryService::OTHER_RECEIVABLES_CODE

  def balance_of(code, as_of: Date.new(2027, 12, 31))
    lines = JournalEntryLine.joins(:journal_entry)
      .where(journal_entries: { company_id: company.id })
      .where(account_code: code)
      .where("journal_entries.date <= ?", as_of)
    lines.sum(:credit_cents) - lines.sum(:debit_cents)
  end

  describe "an expense on account" do
    let!(:expense) do
      Expense.create!(expense_category: category, user: user, company: company,
                      description: "September rent", amount_cents: 30_000,
                      expense_date: Date.new(2026, 9, 1))
    end

    it "charges September and moves no cash" do
      entry = JournalEntry.for_source(expense).sole
      expect(entry.date).to eq(Date.new(2026, 9, 1))
      expect(cash.reload.balance_cents).to eq(100_000)
      expect(balance_of(ACCRUED)).to eq(30_000)
    end

    it "is still owed until a voucher settles it" do
      expect(expense.outstanding_cents).to eq(30_000)
      expect(expense.settled_cents).to eq(0)
    end

    it "takes the cash in October and clears the payable" do
      Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 30_000,
        voucher_date: Date.new(2026, 10, 5),
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call

      expect(cash.reload.balance_cents).to eq(70_000)
      expect(balance_of(ACCRUED)).to eq(0)
      expect(expense.reload.outstanding_cents).to eq(0)
    end

    it "keeps the two dates apart, which is the point" do
      Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 30_000,
        voucher_date: Date.new(2026, 10, 5),
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call

      # Charged in September…
      expect(balance_of(ACCRUED, as_of: Date.new(2026, 9, 30))).to eq(30_000)
      # …paid in October.
      expect(balance_of(ACCRUED, as_of: Date.new(2026, 10, 31))).to eq(0)
    end

    it "carries a part-payment on the payable" do
      Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 10_000,
        voucher_date: Date.new(2026, 10, 5),
        allocations: [{ settles: expense, amount_cents: 10_000 }]
      ).call

      expect(balance_of(ACCRUED)).to eq(20_000)
      expect(expense.reload.outstanding_cents).to eq(20_000)
    end
  end

  describe "an expense paid on the spot" do
    let!(:expense) do
      Expense.create!(expense_category: category, user: user, company: company,
                      treasury: cash, description: "Fuel", amount_cents: 5_000,
                      expense_date: Date.new(2026, 9, 1))
    end

    it "raises its own payment voucher" do
      voucher = Voucher.sole
      expect(voucher.direction).to eq(Voucher::PAYMENT)
      expect(voucher.voucher_date).to eq(Date.new(2026, 9, 1))
      expect(voucher.amount_cents).to eq(5_000)
    end

    it "leaves nothing on the payable, since it was never owed" do
      expect(balance_of(ACCRUED)).to eq(0)
      expect(cash.reload.balance_cents).to eq(95_000)
      expect(expense.outstanding_cents).to eq(0)
    end

    it "voids the voucher and issues a replacement when the amount is edited" do
      original = Voucher.sole

      expense.update!(amount_cents: 8_000)

      expect(cash.reload.balance_cents).to eq(92_000)
      expect(balance_of(ACCRUED)).to eq(0)

      # The old document stays in the book, marked, pointing at its replacement,
      # so the number it used is never handed out again.
      expect(original.reload).to be_voided
      replacement = Voucher.active.sole
      expect(replacement.amount_cents).to eq(8_000)
      expect(original.replaced_by).to eq(replacement)
      expect(Voucher.count).to eq(2)
    end

    it "moves the cash to the other treasury when the treasury is changed" do
      safe = Treasury.create!(name: "Safe", treasury_type: "safe", balance_cents: 50_000,
                              opening_balance_cents: 50_000, company: company)

      expense.update!(treasury: safe)

      expect(cash.reload.balance_cents).to eq(100_000)
      expect(safe.reload.balance_cents).to eq(45_000)
    end

    it "becomes an unpaid accrual when the treasury is cleared" do
      expense.update!(treasury: nil)

      expect(cash.reload.balance_cents).to eq(100_000)
      expect(Voucher.active).to be_empty
      expect(Voucher.voided.sole).to be_present
      expect(balance_of(ACCRUED)).to eq(5_000)
      expect(expense.reload.outstanding_cents).to eq(5_000)
    end

    it "gives the money back when deleted" do
      expense.destroy!

      expect(cash.reload.balance_cents).to eq(100_000)
      expect(Voucher.active).to be_empty
      expect(balance_of(ACCRUED)).to eq(0)
    end
  end

  describe "income earned before it is collected" do
    let!(:income) do
      Income.create!(income_category: income_category, user: user, company: company,
                     description: "September catering", amount_cents: 40_000,
                     income_date: Date.new(2026, 9, 10))
    end

    it "recognises the revenue in September against a receivable" do
      expect(cash.reload.balance_cents).to eq(100_000)
      # Debit balance on 1170, so the credit-less-debit convention is negative.
      expect(balance_of(RECEIVABLE)).to eq(-40_000)
      expect(income.outstanding_cents).to eq(40_000)
    end

    it "collects it in October and clears the receivable" do
      Accounting::RecordVoucherService.new(
        direction: Voucher::RECEIPT, treasury: cash, user: user, amount_cents: 40_000,
        voucher_date: Date.new(2026, 10, 2),
        allocations: [{ settles: income, amount_cents: 40_000 }]
      ).call

      expect(cash.reload.balance_cents).to eq(140_000)
      expect(balance_of(RECEIVABLE)).to eq(0)
      expect(income.reload.outstanding_cents).to eq(0)
    end
  end

  describe "daily COGS, which is a management figure and not a ledger fact" do
    it "posts nothing at all, so no phantom payable appears" do
      cogs = Expense.create!(expense_category: category, user: user, company: company,
                             description: "Cost of sales", amount_cents: 12_000,
                             expense_date: Date.current, is_auto_generated: true)

      expect(JournalEntry.for_source(cogs)).to be_empty
      expect(balance_of(ACCRUED)).to eq(0)
      expect(Voucher.count).to eq(0)
    end
  end
end
