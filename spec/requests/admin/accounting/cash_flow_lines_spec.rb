# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting cash flow lines", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  let!(:cash) do
    Treasury.create!(
      name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 100_000, opening_balance_cents: 100_000, company: company
    )
  end

  before { sign_in owner }

  def lines_path(kind)
    cash_flow_lines_admin_accounting_financial_statements_path(
      start_date: Date.current.beginning_of_month, end_date: Date.current, kind: kind
    )
  end

  describe "the treasury-backed drill-down" do
    let!(:txn) do
      TreasuryTransaction.create!(
        treasury: cash, user: owner, amount_cents: -3_000, kind: "expense",
        description: "Paid out", occurred_on: Date.current,
        balance_after_cents: 97_000, company: company
      )
    end

    it "lists the transactions behind an operating line" do
      get lines_path("expense")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Paid out")
      expect(response.body).to include(ApplicationController.helpers.format_amount(3_000))
    end

    it "shows amounts without the currency symbol" do
      get lines_path("expense")

      expect(response.body).not_to include(ApplicationHelper::MONEY_SYMBOL)
    end
  end

  describe "the CSV export" do
    let!(:txn) do
      TreasuryTransaction.create!(
        treasury: cash, user: owner, amount_cents: -3_000, kind: "expense",
        description: "Paid out", occurred_on: Date.current,
        balance_after_cents: 97_000, company: company
      )
    end

    it "exports the same rows the page shows" do
      get lines_path("expense"), params: { format: :csv }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("cash-flow-expense-")

      rows = CSV.parse(response.body.sub("\ufeff", ""))
      expect(rows.first).to eq([
        I18n.t("shared.date"), I18n.t("accounting.cash_flow.treasury"),
        I18n.t("shared.notes"), I18n.t("shared.amount")
      ])
      expect(rows[1]).to eq([Date.current.to_s, "Cash Drawer", "Paid out", "-30.00"])
      expect(rows.last).to eq([I18n.t("shared.total"), nil, nil, "-30.00"])
    end

    it "leads with a BOM so Excel reads the Arabic headers" do
      get lines_path("expense"), params: { format: :csv }

      expect(response.body).to start_with("\ufeff")
    end

    it "writes amounts as plain decimals a spreadsheet can sum" do
      TreasuryTransaction.create!(
        treasury: cash, user: owner, amount_cents: -1_234_567, kind: "expense",
        description: "Big one", occurred_on: Date.current,
        balance_after_cents: 0, company: company
      )

      get lines_path("expense"), params: { format: :csv }

      # No thousands separator and no currency symbol.
      expect(response.body).to include("-12345.67")
      expect(response.body).not_to include("12,345.67")
      expect(response.body).not_to include(ApplicationHelper::MONEY_SYMBOL)
    end
  end

  # Financing lines are per account and now read cash movement, so the
  # drill-down has to be filtered the same way or the rows will not add up.
  describe "the financing drill-down" do
    let!(:loan) do
      Loan.create!(company: company, name: "Bank loan", loan_type: "bank_loan",
                   principal_cents: 500_000)
    end

    let!(:entry) do
      je = JournalEntry.create!(
        company: company, created_by: owner, date: Date.current,
        description: "Loan drawdown", entry_number: "JE-TEST-1"
      )
      je.lines.create!(account_code: loan.account_code, account_name: "Bank loan",
                       account_type: "liability", credit_cents: 500_000, debit_cents: 0)
      TreasuryTransaction.create!(treasury: cash, user: owner, amount_cents: 500_000,
                                  kind: "journal_entry", description: "Loan drawdown",
                                  occurred_on: Date.current, source_record: je,
                                  balance_after_cents: 0, company: company)
      je
    end

    def loan_lines_path(format: nil)
      cash_flow_lines_admin_accounting_financial_statements_path(
        { start_date: Date.current.beginning_of_month, end_date: Date.current,
          kind: "loan_proceeds", account_code: loan.account_code }.compact.merge(format ? { format: format } : {})
      )
    end

    it "lists the cash behind the financing line" do
      get loan_lines_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Loan drawdown")
      expect(response.body).to include(ApplicationController.helpers.format_amount(500_000))
      expect(response.body).not_to include(ApplicationHelper::MONEY_SYMBOL)
    end

    it "exports it as CSV" do
      get loan_lines_path(format: :csv)

      expect(response).to have_http_status(:ok)
      rows = CSV.parse(response.body.sub("\ufeff", ""))
      expect(rows[1]).to eq([Date.current.to_s, "Cash Drawer", "Loan drawdown", "5000.00"])
    end

    it "shows nothing for an entry on the account that moved no cash" do
      dud = JournalEntry.create!(company: company, created_by: owner, date: Date.current,
                                 description: "Paper only", entry_number: "JE-TEST-2")
      dud.lines.create!(account_code: loan.account_code, account_name: "Bank loan",
                        account_type: "liability", debit_cents: 700_00, credit_cents: 0)

      get cash_flow_lines_admin_accounting_financial_statements_path(
        start_date: Date.current.beginning_of_month, end_date: Date.current,
        kind: "loan_repayment", account_code: loan.account_code
      )

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Paper only")
    end
  end

  describe "an unknown kind" do
    it "falls back to the cash flow statement" do
      get lines_path("not_a_kind")

      expect(response).to redirect_to(
        cash_flow_admin_accounting_financial_statements_path(
          start_date: Date.current.beginning_of_month, end_date: Date.current
        )
      )
    end
  end
end
