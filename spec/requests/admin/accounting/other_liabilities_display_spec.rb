# frozen_string_literal: true

require "rails_helper"

# Tax payable (2100) and equipment payable (2200) are posted by
# JournalEntryService but have no treasury and no model of their own. They used
# to be written to the ledger and rendered nowhere, so both the balance sheet and
# the chart of accounts understated what the company owed.
RSpec.describe "Ledger-only liabilities on the statements", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  before { sign_in owner }

  def post_tax_payable!(amount_cents:, date: Date.current)
    entry = JournalEntry.create!(
      company: company, created_by: owner,
      entry_number: JournalEntry.next_entry_number(company.id),
      date: date, description: "Sales tax", entry_type: "auto"
    )
    entry.lines.create!(account_code: Accounting::JournalEntryService::TAX_PAYABLE_CODE,
                        account_name: "Tax payable", account_type: "liability",
                        debit_cents: 0, credit_cents: amount_cents)
    entry.lines.create!(account_code: 9999, account_name: "Offset",
                        account_type: "expense",
                        debit_cents: amount_cents, credit_cents: 0)
    entry
  end

  it "lists the payable on the chart of accounts" do
    post_tax_payable!(amount_cents: 12_345)

    get admin_accounting_chart_of_accounts_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2100")
    expect(response.body).to include(I18n.t("accounting.chart_of_accounts.group_other_liabilities"))
    expect(response.body).to include(I18n.t("accounting.chart_of_accounts.subtypes.other_payable"))
  end

  it "lists the payable on the balance sheet" do
    post_tax_payable!(amount_cents: 12_345)

    get balance_sheet_admin_accounting_financial_statements_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("2100")
  end

  it "renders both pages when there is nothing of the kind to show" do
    get admin_accounting_chart_of_accounts_path
    expect(response).to have_http_status(:ok)

    get balance_sheet_admin_accounting_financial_statements_path
    expect(response).to have_http_status(:ok)
  end
end
