# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::DigitalWalletDayCloses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:branch) { create(:location, company: company) }
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Cashier drawer",
      treasury_type: "cash_drawer",
      balance_cents: 0,
      active: true
    )
  end

  before { sign_in owner }

  it "shows cashier digital totals and saves statement amounts" do
    session = CashDrawerSession.create!(
      user: cashier,
      treasury: treasury,
      location: branch,
      session_date: BusinessDay.today,
      opening_float_cents: 0,
      status: "reconciled",
      expected_cash_cents: 0,
      counted_cash_cents: 0,
      variance_cents: 0
    )
    order = create(:order, user: cashier, company: company, status: "completed",
      subtotal_cents: 2500, total_cents: 2500)
    create(:payment, order: order, payment_method: "instapay", amount_cents: 2500,
      cash_drawer_session: session)

    get admin_accounting_digital_wallet_day_close_path(date: BusinessDay.today)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(cashier.name)
    expect(response.body).to include(ApplicationController.helpers.format_money(2500))

    patch admin_accounting_digital_wallet_day_close_path(date: BusinessDay.today), params: {
      instapay_statement: "30",
      vodafone_cash_statement: "0",
      notes: "Matched statement"
    }
    expect(response).to redirect_to(admin_accounting_digital_wallet_day_close_path(date: BusinessDay.today))

    day_close = DigitalWalletDayClose.find_by!(business_date: BusinessDay.today, location_id: nil)
    expect(day_close.instapay_statement_cents).to eq(3000)
    expect(day_close.notes).to eq("Matched statement")
  end

  it "scopes sessions and day close to a selected branch" do
    other = create(:location, company: company, name: "Other Branch")
    CashDrawerSession.create!(
      user: cashier,
      treasury: treasury,
      location: branch,
      session_date: BusinessDay.today,
      opening_float_cents: 0,
      status: "reconciled",
      expected_cash_cents: 0,
      counted_cash_cents: 0,
      variance_cents: 0
    )

    get admin_accounting_digital_wallet_day_close_path(date: BusinessDay.today, location_id: other.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(cashier.name)

    patch admin_accounting_digital_wallet_day_close_path(date: BusinessDay.today, location_id: branch.id), params: {
      location_id: branch.id,
      instapay_statement: "10",
      vodafone_cash_statement: "5"
    }
    expect(response).to redirect_to(
      admin_accounting_digital_wallet_day_close_path(date: BusinessDay.today, location_id: branch.id)
    )
    expect(DigitalWalletDayClose.find_by!(business_date: BusinessDay.today, location_id: branch.id)
      .instapay_statement_cents).to eq(1000)
  end
end
