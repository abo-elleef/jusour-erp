# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting KPI scorecard", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 3101) }
  let(:month) { Date.new(2026, 8, 1) }

  before do
    sign_in owner
    JournalEntry.create!(company: company, created_by: owner, date: month + 3, description: "Daily close",
                         entry_number: "JE-KS-1", lines_attributes: [
                           { account_code: 1001, account_name: "Cash", account_type: "asset", debit_cents: 1_000_00, credit_cents: 0 },
                           { account_code: 4001, account_name: "Sales", account_type: "revenue", debit_cents: 0, credit_cents: 1_000_00 }
                         ])
  end

  it "shows six months of KPIs, each month linked to its P&L" do
    get admin_accounting_kpi_scorecard_path(month: "2026-08")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.kpi.rows.gross_margin"), I18n.t("accounting.kpi.rows.cash_cycle"))
    expect(response.body).to include(CGI.escapeHTML(profit_loss_admin_accounting_financial_statements_path(
      start_date: month, end_date: month.end_of_month, transient_range: 1
    )))
  end

  it "shows restaurant ratios only to restaurants" do
    company.update!(business_type: "restaurant")
    get admin_accounting_kpi_scorecard_path(month: "2026-08")
    expect(response.body).to include(I18n.t("accounting.kpi.rows.prime_cost"))
    expect(response.body).not_to include(I18n.t("accounting.kpi.rows.dso"))

    company.update!(business_type: "distribution")
    get admin_accounting_kpi_scorecard_path(month: "2026-08")
    expect(response.body).not_to include(I18n.t("accounting.kpi.rows.prime_cost"))
    expect(response.body).to include(I18n.t("accounting.kpi.rows.dso"))
  end

  it "exports CSV, one column per month" do
    get admin_accounting_kpi_scorecard_path(format: :csv, month: "2026-08")

    expect(response.media_type).to eq("text/csv")
    expect(response.body.lines.first).to include("2026-08", "2026-03")
    expect(response.body).to include("#{I18n.t('accounting.kpi.rows.revenue')},1000.00,")
  end

  it "is listed in the Reports hub" do
    get admin_reports_path

    expect(response.body).to include(admin_accounting_kpi_scorecard_path)
  end
end
