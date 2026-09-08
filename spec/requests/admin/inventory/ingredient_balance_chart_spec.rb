# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingredient balance chart", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 12, company: company)
  end
  let(:supplier) { Supplier.create!(name: "Vendor A", company: company) }

  before { sign_in owner }

  def price(cents, on:)
    SupplierPriceHistory.create!(supplier: supplier, ingredient: ingredient,
      price_cents: cents, effective_date: on)
  end

  it "draws straight segments rather than splines" do
    get admin_inventory_ingredient_path(ingredient)

    # Chartkick maps curve:false to Chart.js tension:0.
    expect(response.body).to include('"curve":false')
  end

  it "adds the price series on its own axis when prices exist" do
    price(1_000, on: Date.current - 3)
    price(1_500, on: Date.current - 1)

    get admin_inventory_ingredient_path(ingredient)

    expect(response.body).to include(I18n.t("inventory.ingredients.show.balance_history.series_price"))
    expect(response.body).to include('"yAxisID":"y1"')
    expect(response.body).to include('"yAxisID":"y"')
    # Price holds flat between receipts, so the second series is stepped.
    expect(response.body).to include('"stepped":true')
  end

  it "hides the price axis and says so when the ingredient was never priced" do
    get admin_inventory_ingredient_path(ingredient)

    expect(response.body).not_to include('"yAxisID":"y1"')
    expect(response.body).to include(I18n.t("inventory.ingredients.show.balance_history.no_price_data"))
  end

  it "keeps the price series inside the selected range" do
    price(9_900, on: Date.current - 60)
    price(1_000, on: Date.current - 2)

    get admin_inventory_ingredient_path(ingredient, chart_days: 7)

    # The 60-day-old price is outside a 7-day window, but it seeded the carry
    # forward, so it appears as the opening value rather than being dropped.
    expect(response.body).to include("99.0")
    expect(response.body).to include("10.0")
  end

  it "offers a two-week range alongside the others" do
    get admin_inventory_ingredient_path(ingredient)

    expect(::Inventory::IngredientBalanceHistoryService::ALLOWED_DAYS).to eq([1, 3, 7, 14, 30, 90])
    expect(response.body).to include(I18n.t("inventory.ingredients.show.balance_history.ranges.14"))
    # Sits between one week and one month, so the list still reads shortest first.
    expect(response.body.index(I18n.t("inventory.ingredients.show.balance_history.ranges.7")))
      .to be < response.body.index(I18n.t("inventory.ingredients.show.balance_history.ranges.14"))
    expect(response.body.index(I18n.t("inventory.ingredients.show.balance_history.ranges.14")))
      .to be < response.body.index(I18n.t("inventory.ingredients.show.balance_history.ranges.30"))
  end

  it "plots fourteen days when two weeks is chosen" do
    get admin_inventory_ingredient_path(ingredient, chart_days: 14)

    history = ::Inventory::IngredientBalanceHistoryService.new(ingredient: ingredient, days: 14).call

    expect(response).to have_http_status(:ok)
    expect(history.size).to eq(14)
    # Fourteen days including today, so the window opens thirteen days back.
    expect(history.keys.map(&:to_date).min).to eq(Date.current - 13)
    expect(history.keys.map(&:to_date).max).to eq(Date.current)
  end

  # Both lines on this chart must cover the same window, or the price line would
  # imply a cost that did not apply to the balance beside it.
  it "keeps the price series on the same fourteen-day window" do
    price(1_000, on: Date.current - 20)
    price(1_500, on: Date.current - 2)

    prices = ::Inventory::IngredientPriceHistoryService.new(ingredient: ingredient, days: 14).call

    expect(prices).to be_present
    expect(prices.keys.map(&:to_date).min).to be >= Date.current - 13
  end

  it "still renders straight lines on the location chart" do
    location = create(:location, :central_kitchen, company: company)
    location.ingredient_locations.create!(ingredient: ingredient, quantity_on_hand: 5,
      reorder_threshold: 1)

    get admin_location_ingredients_path(location, chart_ingredient_ids: [ingredient.id])

    expect(response.body).to include('"curve":false')
  end
end
