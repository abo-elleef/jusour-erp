# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::FinancialStatements", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  before { sign_in owner }

  # ── Shared data ──────────────────────────────────────────────────────────

  let!(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer",
                     balance_cents: 20_000, opening_balance_cents: 20_000, company: company)
  end

  let!(:income_cat) do
    IncomeCategory.create!(name: "POS Sales", category_type: "sales", company: company)
  end

  let!(:expense_cat) do
    ExpenseCategory.create!(name: "Rent", category_type: "rent", company: company)
  end

  let!(:income) do
    Income.create!(
      income_category: income_cat, amount_cents: 50_000,
      income_date: Date.current, description: "Test income",
      recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company
    )
  end

  let!(:expense) do
    Expense.create!(
      expense_category: expense_cat, amount_cents: 15_000,
      expense_date: Date.current, description: "Test expense",
      recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company
    )
  end

  # ── P&L ──────────────────────────────────────────────────────────────────

  describe "GET /admin/accounting/financial_statements/profit_loss" do
    it "returns 200" do
      get profit_loss_admin_accounting_financial_statements_path
      expect(response).to have_http_status(:ok)
    end

    it "defaults to year-to-date range" do
      get profit_loss_admin_accounting_financial_statements_path
      expect(response.body).to include(Date.current.year.to_s)
    end

    it "shows revenue lines" do
      get profit_loss_admin_accounting_financial_statements_path
      expect(response.body).to include("POS Sales")
    end

    it "shows expense lines" do
      get profit_loss_admin_accounting_financial_statements_path
      expect(response.body).to include("Rent")
    end

    it "respects the start_date / end_date params" do
      Income.create!(
        income_category: income_cat, amount_cents: 99_000,
        income_date: 1.year.from_now.to_date, description: "Future income",
        recurrence: "one_time", user: owner, treasury: cash,
        is_auto_generated: false, company: company
      )

      # Request only today's range — future income must not appear in revenue total
      get profit_loss_admin_accounting_financial_statements_path,
          params: { start_date: Date.current.to_s, end_date: Date.current.to_s }

      expect(response).to have_http_status(:ok)
      # The future income is excluded; only 50_000 is in range
      expect(response.body).not_to include("ج.م.1,490.00") # 50_000 + 99_000 / 100
    end

    it "shows net income" do
      get profit_loss_admin_accounting_financial_statements_path
      expect(response.body).to include("صافي الربح")
    end

    context "when there is no revenue" do
      before { Income.destroy_all }

      it "shows the empty-revenue message" do
        get profit_loss_admin_accounting_financial_statements_path
        expect(response.body).to include(I18n.t("accounting.financial_statements.no_revenue"))
      end
    end

    context "when there are no expenses" do
      before { Expense.destroy_all }

      it "shows the empty-expense message" do
        get profit_loss_admin_accounting_financial_statements_path
        expect(response.body).to include(I18n.t("accounting.financial_statements.no_expenses"))
      end
    end

    context "PDF format" do
      it "returns a PDF file" do
        get profit_loss_admin_accounting_financial_statements_path(
          start_date: Date.current.beginning_of_year.to_s,
          end_date: Date.current.to_s,
          format: :pdf
        )
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/pdf")
        expect(response.body[0..3]).to eq("%PDF")
      end

      it "sets a descriptive filename" do
        get profit_loss_admin_accounting_financial_statements_path(
          start_date: "2026-01-01", end_date: "2026-07-17", format: :pdf
        )
        expect(response.headers["Content-Disposition"]).to include("profit_loss_2026-01-01_2026-07-17.pdf")
      end
    end
  end

  # ── Balance Sheet ─────────────────────────────────────────────────────────

  describe "GET /admin/accounting/financial_statements/balance_sheet" do
    it "returns 200" do
      get balance_sheet_admin_accounting_financial_statements_path
      expect(response).to have_http_status(:ok)
    end

    it "shows asset lines" do
      get balance_sheet_admin_accounting_financial_statements_path
      expect(response.body).to include("Cash")
    end

    it "shows total assets" do
      get balance_sheet_admin_accounting_financial_statements_path
      expect(response.body).to include(I18n.t("accounting.financial_statements.total_assets"))
    end

    it "shows the equity section" do
      get balance_sheet_admin_accounting_financial_statements_path
      expect(response.body).to include(I18n.t("accounting.financial_statements.equity"))
    end

    it "accepts an as_of param" do
      get balance_sheet_admin_accounting_financial_statements_path,
          params: { as_of: "2026-06-30" }
      expect(response).to have_http_status(:ok)
    end

    it "shows the liabilities + equity balance check row" do
      get balance_sheet_admin_accounting_financial_statements_path
      expect(response.body).to include(I18n.t("accounting.financial_statements.liabilities_plus_equity"))
    end

    context "with loans" do
      let!(:loan) do
        Loan.create!(
          name: "Bank Loan", loan_type: "bank_loan",
          principal_cents: 100_000, interest_rate: 5.0,
          company: company
        )
      end

      it "includes loans in the liabilities section" do
        get balance_sheet_admin_accounting_financial_statements_path
        expect(response.body).to include("Bank Loan")
        expect(response.body).to include(I18n.t("accounting.financial_statements.total_liabilities"))
      end
    end

    context "PDF format" do
      it "returns a PDF file" do
        get balance_sheet_admin_accounting_financial_statements_path(
          as_of: Date.current.to_s, format: :pdf
        )
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/pdf")
        expect(response.body[0..3]).to eq("%PDF")
      end

      it "sets a descriptive filename" do
        get balance_sheet_admin_accounting_financial_statements_path(
          as_of: "2026-07-17", format: :pdf
        )
        expect(response.headers["Content-Disposition"]).to include("balance_sheet_2026-07-17.pdf")
      end
    end
  end

  # ── Cash Flow ─────────────────────────────────────────────────────────────

  describe "GET /admin/accounting/financial_statements/cash_flow" do
    it "returns 200" do
      get cash_flow_admin_accounting_financial_statements_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the three section headings" do
      get cash_flow_admin_accounting_financial_statements_path
      expect(response.body).to include(I18n.t("accounting.cash_flow.operating_activities"))
      expect(response.body).to include(I18n.t("accounting.cash_flow.investing_activities"))
      expect(response.body).to include(I18n.t("accounting.cash_flow.financing_activities"))
    end

    it "shows the ending balance" do
      get cash_flow_admin_accounting_financial_statements_path
      expect(response.body).to include(I18n.t("accounting.cash_flow.ending_balance"))
    end

    it "defaults to year-to-date" do
      get cash_flow_admin_accounting_financial_statements_path
      expect(response.body).to include(Date.current.year.to_s)
    end

    context "PDF format" do
      it "returns a valid PDF" do
        get cash_flow_admin_accounting_financial_statements_path(
          start_date: Date.current.beginning_of_year.to_s,
          end_date: Date.current.to_s,
          format: :pdf
        )
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/pdf")
        expect(response.body[0..3]).to eq("%PDF")
      end

      it "sets a descriptive filename" do
        get cash_flow_admin_accounting_financial_statements_path(
          start_date: "2026-01-01", end_date: "2026-07-17", format: :pdf
        )
        expect(response.headers["Content-Disposition"]).to include("cash_flow_2026-01-01_2026-07-17.pdf")
      end
    end
  end

  # ── Auth ──────────────────────────────────────────────────────────────────

  describe "access control" do
    before { sign_out owner }

    it "redirects unauthenticated requests to sign in" do
      get profit_loss_admin_accounting_financial_statements_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects balance sheet for unauthenticated users" do
      get balance_sheet_admin_accounting_financial_statements_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
