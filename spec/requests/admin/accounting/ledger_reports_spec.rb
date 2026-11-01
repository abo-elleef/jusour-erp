# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting trial balance and general ledger", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2701) }
  let(:cash) do
    Treasury.create!(name: "Main safe", treasury_type: "safe", balance_cents: 0, opening_balance_cents: 0, company: company)
  end

  before do
    sign_in owner
    JournalEntry.create!(company: company, created_by: owner, date: Date.current, description: "Cash sale",
                         entry_number: "JE-R-0001", lines_attributes: [
                           { account_code: cash.to_account.code, account_name: cash.name, account_type: "asset",
                             debit_cents: 1_500_00, credit_cents: 0, treasury_id: cash.id },
                           { account_code: 4001, account_name: "Sales", account_type: "revenue",
                             debit_cents: 0, credit_cents: 1_500_00 }
                         ])
  end

  def range = { start_date: Date.current.beginning_of_month, end_date: Date.current }

  it "shows a balanced trial balance whose accounts open their general ledger" do
    get trial_balance_admin_accounting_ledger_reports_path(range)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.ledger.trial_balance.stats.balanced"), "Main safe", "Sales")
    expect(response.body).to include(CGI.escapeHTML(general_ledger_admin_accounting_ledger_reports_path(account: "c:4001", **range)))
  end

  it "shows an account's lines in the general ledger, linked to their journal entry" do
    get general_ledger_admin_accounting_ledger_reports_path(account: "t:#{cash.id}", **range)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cash sale", "JE-R-0001", "1,500")
    expect(response.body).to include(admin_accounting_journal_entry_path(JournalEntry.find_by(entry_number: "JE-R-0001")))
  end

  it "asks for an account when none is chosen" do
    get general_ledger_admin_accounting_ledger_reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.ledger.general_ledger.pick_hint"))
  end

  it "exports both as CSV with plain amounts" do
    get trial_balance_admin_accounting_ledger_reports_path(format: :csv, **range)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("4001,Sales")
    expect(response.body).to include("1500.00")

    get general_ledger_admin_accounting_ledger_reports_path(format: :csv, account: "c:4001", **range)
    expect(response.body).to include("JE-R-0001,Cash sale,0.00,1500.00,-1500.00")
  end

  it "is listed in the Reports hub" do
    get admin_reports_path

    expect(response.body).to include(trial_balance_admin_accounting_ledger_reports_path)
    expect(response.body).to include(general_ledger_admin_accounting_ledger_reports_path)
  end

  it "needs the accounting:reports permission" do
    sign_in create(:user, company: company, wages_account_code: 2702)

    get trial_balance_admin_accounting_ledger_reports_path

    expect(response).not_to have_http_status(:ok)
  end
end
