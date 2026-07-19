# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::Expenses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  let!(:cash) do
    Treasury.create!(
      name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 100_000, opening_balance_cents: 100_000, company: company
    )
  end

  let!(:category) do
    ExpenseCategory.create!(name: "Supplies", category_type: "other", position: 1, company: company)
  end

  before { sign_in owner }

  def create_expense(amount_cents: 20_000)
    Expense.create!(
      expense_category: category, amount_cents: amount_cents,
      expense_date: Date.current, description: "Office supplies",
      recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company
    )
  end

  def post_reverse(expense)
    post reverse_admin_accounting_expense_path(expense)
  end

  # ── Reversal ─────────────────────────────────────────────────────────────

  describe "POST /admin/accounting/expenses/:id/reverse" do
    it "preserves the original journal entry (does not delete it)" do
      expense = create_expense
      je = JournalEntry.for_source(expense).first
      post_reverse(expense)
      expect(JournalEntry.exists?(je.id)).to be true
    end

    it "creates a new reversal journal entry" do
      expense = create_expense
      expect { post_reverse(expense) }.to change(JournalEntry, :count).by(1)
      reversal = JournalEntry.last
      expect(reversal.entry_type).to eq("reversal")
    end

    it "reversal entry flips debit/credit lines" do
      expense = create_expense(amount_cents: 10_000)
      je = JournalEntry.for_source(expense).first
      post_reverse(expense)
      reversal = JournalEntry.last

      je.lines.each do |original_line|
        rev_line = reversal.lines.find { |l| l.account_code == original_line.account_code }
        expect(rev_line.debit_cents).to eq(original_line.credit_cents)
        expect(rev_line.credit_cents).to eq(original_line.debit_cents)
      end
    end

    it "cancels the treasury balance effect (net zero after reversal)" do
      expense = create_expense(amount_cents: 5_000)
      balance_after_expense = cash.reload.balance_cents
      post_reverse(expense)
      expect(cash.reload.balance_cents).to eq(balance_after_expense + 5_000)
    end

    it "creates TreasuryTransactions for the reversal entry" do
      expense = create_expense
      post_reverse(expense)
      reversal = JournalEntry.last
      txns = TreasuryTransaction.where(source_record: reversal)
      expect(txns.count).to be >= 1
    end

    it "stamps reversed_at on the expense" do
      expense = create_expense
      expect { post_reverse(expense) }
        .to change { expense.reload.reversed_at }.from(nil)
    end

    it "redirects to expenses index with a notice" do
      expense = create_expense
      post_reverse(expense)
      expect(response).to redirect_to(admin_accounting_expenses_path)
      expect(flash[:notice]).to be_present
    end

    it "cannot reverse an already-reversed expense" do
      expense = create_expense
      post_reverse(expense)
      je_count_before = JournalEntry.count
      post_reverse(expense)
      expect(JournalEntry.count).to eq(je_count_before)
      expect(response).to redirect_to(admin_accounting_expenses_path)
      expect(flash[:alert]).to be_present
    end

    it "redirects with alert if no journal entry exists" do
      expense = create_expense
      JournalEntry.for_source(expense).destroy_all
      post_reverse(expense)
      expect(flash[:alert]).to be_present
    end
  end

  # ── Edit/Update blocked for reversed expenses ─────────────────────────────

  describe "GET /admin/accounting/expenses/:id/edit (reversed)" do
    it "redirects with alert instead of showing the form" do
      expense = create_expense
      post_reverse(expense)
      get edit_admin_accounting_expense_path(expense)
      expect(response).to redirect_to(admin_accounting_expenses_path)
      expect(flash[:alert]).to be_present
    end
  end

  describe "PATCH /admin/accounting/expenses/:id (reversed)" do
    it "redirects with alert and does not update the record" do
      expense = create_expense(amount_cents: 20_000)
      post_reverse(expense)
      patch admin_accounting_expense_path(expense), params: {
        expense: { amount_pounds: "999" }
      }
      expect(expense.reload.amount_cents).to eq(20_000)
      expect(response).to redirect_to(admin_accounting_expenses_path)
      expect(flash[:alert]).to be_present
    end

    it "does not trigger JE recreation (no FK violation, no new JE)" do
      expense = create_expense
      post_reverse(expense)
      je_count_before = JournalEntry.count
      patch admin_accounting_expense_path(expense), params: {
        expense: { amount_pounds: "999" }
      }
      expect(JournalEntry.count).to eq(je_count_before)
    end
  end

  # ── Model validation ─────────────────────────────────────────────────────

  describe "Expense model — immutable_once_reversed" do
    it "prevents update via model when reversed_at is set" do
      expense = create_expense
      expense.update_column(:reversed_at, Time.current)
      result = expense.update(amount_cents: 99_999)
      expect(result).to be false
      expect(expense.errors[:base]).to be_present
      expect(expense.reload.amount_cents).not_to eq(99_999)
    end

    it "allows update_column to bypass the validation (needed internally)" do
      expense = create_expense
      expect { expense.update_column(:reversed_at, Time.current) }.not_to raise_error
    end
  end
end
