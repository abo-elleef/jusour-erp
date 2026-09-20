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

  def money(cents) = ApplicationController.helpers.format_amount(cents)

  def create_expense(amount_cents: 20_000)
    Expense.create!(
      expense_category: category, amount_cents: amount_cents,
      expense_date: Date.current, description: "Office supplies",
      recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company
    )
  end

  describe "GET /admin/accounting/expenses" do
    # Every row listed is a live one now: undoing an expense deletes it rather
    # than flagging it, so the total is simply the sum of what is there.
    it "shows the sum of expenses in the selected range" do
      create_expense(amount_cents: 20_000)
      create_expense(amount_cents: 15_000)

      get admin_accounting_expenses_path(start_date: Date.current.beginning_of_month, end_date: Date.current)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(money(35_000))
      expect(response.body).to include(I18n.t("accounting.expenses.stats_spent"))
    end

    it "drops a deleted expense out of the total" do
      create_expense(amount_cents: 20_000)
      gone = create_expense(amount_cents: 50_000)

      delete admin_accounting_expense_path(gone)
      get admin_accounting_expenses_path(start_date: Date.current.beginning_of_month, end_date: Date.current)

      expect(response.body).to include(money(20_000))
      expect(response.body).not_to include(money(70_000))
    end

    it "renders the ledger tab with bare amounts and no currency symbol" do
      create_expense(amount_cents: 20_000)

      get admin_accounting_expenses_path(
        start_date: Date.current.beginning_of_month, end_date: Date.current, tab: "ledger"
      )
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.expenses.ledger.total"))
      expect(response.body).not_to include(ApplicationHelper::MONEY_SYMBOL)
    end
  end

  # Deleting used to be impossible by route, and the model deliberately kept the
  # journal entry when a record was destroyed by other means. Both are reversed,
  # and reversal itself is gone: a deleted expense takes its ledger with it, so
  # the P&L stops reporting money against a row nobody can open.
  describe "DELETE /admin/accounting/expenses/:id" do
    # The cash now belongs to the payment voucher the expense raised, not to the
    # expense, so deleting has to take the voucher with it or the money never
    # comes back.
    it "deletes the expense, its journal entry and the voucher that paid it" do
      expense = create_expense(amount_cents: 20_000)
      voucher = Voucher.sole
      expect(JournalEntry.for_source(expense)).to exist
      expect(TreasuryTransaction.where(source_record: voucher)).to exist

      expect { delete admin_accounting_expense_path(expense) }
        .to change(Expense, :count).by(-1)
        .and change { Voucher.active.count }.by(-1)

      expect(JournalEntry.where(source_record_type: "Expense", source_record_id: expense.id)).to be_empty
      expect(TreasuryTransaction.where(source_record_type: "Voucher", source_record_id: voucher.id)).to be_empty
    end

    it "restores the treasury balance" do
      expense = create_expense(amount_cents: 20_000)
      expect(cash.reload.balance_cents).to eq(80_000)

      delete admin_accounting_expense_path(expense)

      expect(cash.reload.balance_cents).to eq(100_000)
    end

    it "leaves no journal lines behind" do
      expense = create_expense
      entry_id = JournalEntry.for_source(expense).first.id

      delete admin_accounting_expense_path(expense)

      expect(JournalEntryLine.where(journal_entry_id: entry_id)).to be_empty
    end

    it "records an audit entry carrying what was deleted" do
      expense = create_expense(amount_cents: 20_000)

      delete admin_accounting_expense_path(expense)

      audit = AuditLogEntry.find_by(action: "expense.destroy", record_id: expense.id)
      expect(audit).to be_present
      expect(audit.changes_snapshot["amount_cents"]).to eq(20_000)
      expect(audit.changes_snapshot["description"]).to eq("Office supplies")
    end
  end
end
