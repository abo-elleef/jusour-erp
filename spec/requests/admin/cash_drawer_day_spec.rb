# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The admin drawer day view", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 12, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Branch A") }
  let(:manager) { create(:user, :manager, company: company) }
  let!(:till_one) do
    Treasury.create!(company: company, name: "Till 1", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0)
  end
  let!(:till_two) do
    Treasury.create!(company: company, name: "Till 2", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0)
  end

  before do
    Current.company = company
    sign_in manager
  end

  def shift(treasury:, cash: 0)
    session = CashDrawerSession.create!(
      company: company, user: create(:user, company: company), treasury: treasury,
      location: branch, session_date: Date.current, opening_float_cents: 10_000, status: "open"
    )
    if cash.positive?
      order = create(:order, user: session.user, company: company, location: branch,
                             status: "completed", total_cents: cash)
      create(:payment, order: order, amount_cents: cash, status: "completed",
                       payment_method: "cash", cash_drawer_session: session)
    end
    session
  end

  it "summarises the day's shifts for a branch" do
    shift(treasury: till_one, cash: 5_000)
    shift(treasury: till_two, cash: 3_000)

    get admin_accounting_cash_drawer_index_path(date: Date.current, location_id: branch.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("accounting.cash_drawer.day_summary"))
    expect(response.body).to include(I18n.t("accounting.cash_drawer.still_open", count: 2))
  end

  it "narrows to a single drawer when one is chosen" do
    shift(treasury: till_one, cash: 5_000)
    shift(treasury: till_two, cash: 3_000)

    get admin_accounting_cash_drawer_index_path(
      date: Date.current, location_id: branch.id, treasury_id: till_one.id
    )

    expect(response.body).to include(I18n.t("accounting.cash_drawer.still_open", count: 1))
  end

  it "offers the drawer filter with an all-drawers option" do
    get admin_accounting_cash_drawer_index_path(date: Date.current, location_id: branch.id)

    expect(response.body).to include(I18n.t("accounting.cash_drawer.all_drawers"))
    expect(response.body).to include("Till 1")
  end

  it "localises the drawer status instead of falling back to humanize" do
    shift(treasury: till_one)

    get admin_accounting_cash_drawer_index_path(date: Date.current, location_id: branch.id, locale: :ar)

    expect(response.body).to include(I18n.t("accounting.cash_drawer.statuses.open", locale: :ar))
  end
end
