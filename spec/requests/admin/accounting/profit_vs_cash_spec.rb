# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting profit vs cash", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  let!(:cash) do
    Treasury.create!(name: "Cash Drawer", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  before { sign_in owner }

  def page_path
    profit_vs_cash_admin_accounting_financial_statements_path(
      start_date: Date.current.beginning_of_month, end_date: Date.current.end_of_month
    )
  end

  it "renders the bridge between the two statements" do
    JournalEntry.create!(company: company, created_by: owner, date: Date.current,
                         description: "Sales", entry_number: "JE-PVC-1")
      .lines.create!(account_code: 4001, account_name: "Sales", account_type: "revenue",
                     credit_cents: 1_000_00, debit_cents: 0)
    InventorySnapshot.create!(company: company, snapshot_date: Date.current.beginning_of_month - 1,
                              value_cents: 100_00)
    InventorySnapshot.create!(company: company, snapshot_date: Date.current.end_of_month,
                              value_cents: 250_00)

    get page_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.profit_vs_cash.net_profit"))
    expect(response.body).to include(I18n.t("accounting.profit_vs_cash.cash_change"))
    expect(response.body).to include(I18n.t("accounting.profit_vs_cash.lines.inventory_build"))
  end

  it "says so plainly when there is nothing to explain" do
    get page_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.profit_vs_cash.no_gap"))
  end

  it "follows the no-currency-in-views rule" do
    get page_path

    expect(response.body).not_to include(ApplicationHelper::MONEY_SYMBOL)
  end

  it "appears in the accounting reports nav" do
    get cash_flow_admin_accounting_financial_statements_path

    expect(response.body).to include(I18n.t("accounting.nav.profit_vs_cash"))
    expect(response.body).to include("/admin/accounting/financial_statements/profit_vs_cash")
  end
end
