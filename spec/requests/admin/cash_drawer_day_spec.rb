# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The admin drawer day view", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 12, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Branch A") }
  let!(:other_branch) { create(:location, company: company, name: "Branch B") }
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

  def shift(treasury:, cash: 0, location: branch)
    session = CashDrawerSession.create!(
      company: company, user: create(:user, company: company), treasury: treasury,
      location: location, session_date: Date.current, opening_float_cents: 10_000, status: "open"
    )
    if cash.positive?
      order = create(:order, user: session.user, company: company, location: location,
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

  describe "the table's totals row" do
    def totals_row
      Nokogiri::HTML(response.body).at_css("table tfoot tr")
    end

    it "sums the shifts of every branch when no branch is chosen" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, cash: 3_000, location: other_branch)

      get admin_accounting_cash_drawer_index_path(date: Date.current)

      expect(totals_row.text).to include(I18n.t("accounting.cash_drawer.table_total"))
      expect(totals_row.text).to include(ApplicationController.helpers.format_money(8_000))
    end

    it "sums only the chosen branch's shifts" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, cash: 3_000, location: other_branch)

      get admin_accounting_cash_drawer_index_path(date: Date.current, location_id: branch.id)

      expect(totals_row.text).to include(ApplicationController.helpers.format_money(5_000))
      expect(totals_row.text).not_to include(ApplicationController.helpers.format_money(8_000))
    end

    it "is left out when there are no shifts" do
      get admin_accounting_cash_drawer_index_path(date: Date.current)

      expect(totals_row).to be_nil
    end
  end

  describe "across every branch" do
    it "defaults to all branches rather than whichever comes first" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, cash: 3_000, location: other_branch)

      get admin_accounting_cash_drawer_index_path(date: Date.current)

      expect(response.body).to include(I18n.t("accounting.cash_drawer.still_open", count: 2))
      expect(response.body).to include("Branch A")
      expect(response.body).to include("Branch B")
    end

    it "offers the all-branches option in the filter" do
      get admin_accounting_cash_drawer_index_path(date: Date.current)

      expect(response.body).to include(I18n.t("accounting.cash_drawer.all_locations"))
    end

    it "still narrows to one branch when one is chosen" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, cash: 3_000, location: other_branch)

      get admin_accounting_cash_drawer_index_path(date: Date.current, location_id: branch.id)

      expect(response.body).to include(I18n.t("accounting.cash_drawer.still_open", count: 1))
    end

    it "combines a branch and a drawer filter" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, cash: 3_000)
      shift(treasury: till_one, cash: 9_000, location: other_branch)

      get admin_accounting_cash_drawer_index_path(
        date: Date.current, location_id: branch.id, treasury_id: till_one.id
      )

      expect(response.body).to include(I18n.t("accounting.cash_drawer.still_open", count: 1))
    end
  end
end
