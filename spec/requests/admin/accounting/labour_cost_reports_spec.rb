# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting labour cost report", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2901) }
  let(:month) { Date.current.prev_month.beginning_of_month }

  before do
    sign_in owner
    JournalEntry.create!(company: company, created_by: owner, date: month + 2, description: "Daily close",
                         entry_number: "JE-LC-1", lines_attributes: [
                           { account_code: 1001, account_name: "Cash", account_type: "asset", debit_cents: 2_000_00, credit_cents: 0 },
                           { account_code: 4001, account_name: "Sales", account_type: "revenue", debit_cents: 0, credit_cents: 2_000_00 }
                         ])
    PayrollSnapshot.create!(company: company, user: create(:user, company: company, wages_account_code: 2902),
                            finalized_by: owner, payroll_month: month, finalized_at: Time.current, net_pay_cents: 300_00)
  end

  def range = { start_date: month, end_date: month.end_of_month }

  it "shows the month's labour share, linked to its payroll" do
    get admin_accounting_labour_cost_reports_path(range)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("15.0%")
    expect(response.body).to include(CGI.escapeHTML(admin_accounting_monthly_payroll_path(payroll_month: month.strftime("%Y-%m"))))
  end

  it "exports CSV with plain amounts" do
    get admin_accounting_labour_cost_reports_path(format: :csv, **range)

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("#{month.strftime('%Y-%m')},2000.00,300.00,15.0,1,300.00")
  end

  it "is listed in the Reports hub" do
    get admin_reports_path

    expect(response.body).to include(admin_accounting_labour_cost_reports_path)
  end

  it "needs the payroll:view permission" do
    sign_in create(:user, company: company, wages_account_code: 2903)

    get admin_accounting_labour_cost_reports_path

    expect(response).not_to have_http_status(:ok)
  end
end
