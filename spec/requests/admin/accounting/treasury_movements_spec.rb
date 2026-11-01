# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting treasury movement summary", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 3401) }
  let(:safe) { Treasury.create!(name: "Main safe", treasury_type: "safe", balance_cents: 0, opening_balance_cents: 0, company: company) }

  before do
    sign_in owner
    TreasuryTransaction.create!(treasury: safe, user: owner, amount_cents: 2_500_00, kind: "income",
                                description: "Day close", occurred_on: Date.current, balance_after_cents: 2_500_00)
  end

  def range = { start_date: Date.current.beginning_of_month, end_date: Date.current }

  it "lists each treasury linked to its own movements" do
    get admin_accounting_treasury_movements_path(range)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Main safe", "2,500")
    expect(response.body).to include(CGI.escapeHTML(admin_accounting_treasury_path(safe, **range)))
  end

  it "exports CSV with plain amounts" do
    get admin_accounting_treasury_movements_path(format: :csv, **range)

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Main safe,")
    expect(response.body).to include("0.00,2500.00,0.00,0.00,2500.00")
  end

  it "is listed in the Reports hub" do
    get admin_reports_path

    expect(response.body).to include(admin_accounting_treasury_movements_path)
  end
end
