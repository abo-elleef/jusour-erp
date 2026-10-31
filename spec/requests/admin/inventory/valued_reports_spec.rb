# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory valued reports", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:location) { create(:location, company: company) }
  let(:flour) { create(:ingredient, company: company, ingredient_category: category, name: "Report Flour") }

  before do
    Current.company = company
    sign_in owner
    flour.ingredient_locations.create!(location: location, quantity_on_hand: 0, reorder_threshold: 5, max_quantity: 10)
    StockAdjustment.create!(ingredient: flour, user: owner, location: location, quantity_delta: 3,
      adjustment_type: "manual_add", unit_cost_cents: 250)
  end

  dates = { start_date: Date.current.beginning_of_month, end_date: Date.current }
  {
    item_card: dates, adjustments: dates, stock_levels: { status: "all" },
    stagnant_items: { days: 1 }, turnover: dates
  }.each do |report, query|
    it "renders #{report} with the item, as CSV, and as a print view" do
      path = "/admin/inventory/reports/#{report}"

      get path, params: query
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("translation missing")

      get "#{path}.csv", params: query
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")

      get path, params: query.merge(print: 1)
      expect(response.body).to include('data-controller="auto-print"')
    end
  end

  it "shows one item's card with its opening, movements and totals" do
    get "/admin/inventory/reports/item_card", params: dates.merge(ingredient_id: flour.id)

    expect(response.body).to include("Report Flour")
    expect(response.body).to include(I18n.t("inventory.reports.item_card.opening"))
  end

  it "keeps another company's items out" do
    other = create(:company)
    Current.company = other
    stranger = create(:ingredient, company: other, ingredient_category: create(:ingredient_category, company: other),
      name: "Stranger Salt")
    StockAdjustment.create!(ingredient: stranger, user: create(:user, :owner, company: other), quantity_delta: 9,
      adjustment_type: "manual_add", unit_cost_cents: 100)
    Current.company = company

    get "/admin/inventory/reports/item_card", params: dates
    expect(response.body).not_to include("Stranger Salt")
  end
end
