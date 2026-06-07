# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::TreasuryLedgerService do
  let(:user) { create(:user) }
  let(:treasury) do
    Treasury.create!(
      name: "Test Safe",
      treasury_type: "safe",
      opening_balance_cents: 100_000,
      balance_cents: 100_000,
      company: Current.company
    )
  end
  let(:expense_category) do
    ExpenseCategory.create!(name: "Supplies", category_type: "other", position: 1, company: Current.company)
  end
  let(:income_category) do
    IncomeCategory.create!(name: "Catering", category_type: "catering", position: 1, company: Current.company)
  end

  describe ".sync_expense!" do
    it "deducts from treasury balance" do
      expense = Expense.create!(
        expense_category: expense_category,
        user: user,
        treasury: treasury,
        description: "Paper towels",
        amount_cents: 5_000,
        expense_date: Date.current
      )

      treasury.reload
      expect(treasury.balance_cents).to eq(95_000)
      expect(treasury.treasury_transactions.last).to have_attributes(
        kind: "expense",
        amount_cents: -5_000,
        balance_after_cents: 95_000
      )
    end

    it "reverses and re-applies when expense treasury changes" do
      other = Treasury.create!(
        name: "Petty Cash",
        treasury_type: "petty_cash",
        opening_balance_cents: 20_000,
        balance_cents: 20_000
      )
      expense = Expense.create!(
        expense_category: expense_category,
        user: user,
        treasury: treasury,
        description: "Supplies",
        amount_cents: 3_000,
        expense_date: Date.current
      )

      expense.update!(treasury: other)

      expect(treasury.reload.balance_cents).to eq(100_000)
      expect(other.reload.balance_cents).to eq(17_000)
    end
  end

  describe ".sync_income!" do
    it "adds to treasury balance" do
      Income.create!(
        income_category: income_category,
        user: user,
        treasury: treasury,
        description: "Catering order",
        amount_cents: 12_000,
        income_date: Date.current
      )

      expect(treasury.reload.balance_cents).to eq(112_000)
    end
  end

  describe ".sync_drawer_open!" do
    it "deducts opening float from drawer treasury" do
      drawer = Treasury.create!(
        name: "Register 1",
        treasury_type: "cash_drawer",
        opening_balance_cents: 30_000,
        balance_cents: 30_000
      )
      session = CashDrawerSession.create!(
        user: user,
        treasury: drawer,
        session_date: Date.current,
        shift: "morning",
        opening_float_cents: 10_000,
        status: "open"
      )

      described_class.sync_drawer_open!(session)

      expect(drawer.reload.balance_cents).to eq(20_000)
    end
  end

  describe "#record_adjustment!" do
    it "updates balance for manual adjustments" do
      described_class.new.record_adjustment!(
        treasury: treasury,
        user: user,
        amount_cents: -2_000,
        description: "Bank deposit"
      )

      expect(treasury.reload.balance_cents).to eq(98_000)
    end
  end

  describe ".create_transfer!" do
    let(:destination) do
      Treasury.create!(
        name: "Bank Account",
        treasury_type: "bank",
        opening_balance_cents: 50_000,
        balance_cents: 50_000
      )
    end

    it "moves money between treasuries with paired ledger entries" do
      transfer = TreasuryTransfer.new(
        from_treasury: treasury,
        to_treasury: destination,
        user: user,
        amount_cents: 15_000,
        description: "End-of-day deposit",
        occurred_on: Date.current
      )

      described_class.create_transfer!(transfer)

      expect(treasury.reload.balance_cents).to eq(85_000)
      expect(destination.reload.balance_cents).to eq(65_000)

      outbound = treasury.treasury_transactions.last
      inbound = destination.treasury_transactions.last
      expect(outbound).to have_attributes(kind: "transfer", amount_cents: -15_000, source_record: transfer)
      expect(inbound).to have_attributes(kind: "transfer", amount_cents: 15_000, source_record: transfer)
    end

    it "does not persist transfer when source balance is insufficient" do
      transfer = TreasuryTransfer.new(
        from_treasury: treasury,
        to_treasury: destination,
        user: user,
        amount_cents: 200_000,
        description: "Too much",
        occurred_on: Date.current
      )

      expect { described_class.create_transfer!(transfer) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(TreasuryTransfer.count).to eq(0)
      expect(treasury.reload.balance_cents).to eq(100_000)
      expect(destination.reload.balance_cents).to eq(50_000)
    end
  end
end
