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

  describe "filtering the balance by location" do
    let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
    let(:branch) { create(:location, company: company, name: "Branch A") }

    def unit_label
      ApplicationController.helpers.ingredient_unit_label(ingredient.unit)
    end

    def stock_at(location, on_hand)
      location.ingredient_locations.create!(ingredient: ingredient, quantity_on_hand: on_hand,
        reorder_threshold: 1)
    end

    def adjust(location, delta, on: Time.current)
      StockAdjustment.create!(ingredient: ingredient, user: owner, location: location,
        quantity_delta: delta, adjustment_type: "manual_add", created_at: on, updated_at: on)
    end

    it "offers every stock location plus an all-locations default" do
      stock_at(kitchen, 8)
      stock_at(branch, 4)

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).to include(I18n.t("inventory.ingredients.show.balance_history.all_locations"))
      expect(response.body).to include("Central Kitchen", "Branch A")
      expect(response.body).to include("chart_location_id")
    end

    it "walks only the chosen location's movements" do
      stock_at(kitchen, 8)
      stock_at(branch, 4)
      adjust(kitchen, 3, on: 1.day.ago)
      adjust(branch, 1, on: 1.day.ago)

      kitchen_series = ::Inventory::IngredientBalanceHistoryService.new(
        ingredient: ingredient, days: 7, location: kitchen
      ).call
      branch_series = ::Inventory::IngredientBalanceHistoryService.new(
        ingredient: ingredient, days: 7, location: branch
      ).call

      # Recording the adjustment applies its delta, so the kitchen now holds 11
      # and the walk backwards puts it at 8 before that movement.
      expect(kitchen_series.values.last).to eq(11.0)
      expect(kitchen_series.values.first).to eq(8.0)
      # The point of the filter: each location stands on its own, and neither is
      # the ingredient's company-wide total.
      expect(branch_series.values.last).to eq(5.0)
      expect(kitchen_series.values.last).not_to eq(branch_series.values.last)
      expect(kitchen_series.values.last).not_to eq(ingredient.reload.quantity_on_hand.to_f)
    end

    it "leaves the company-wide series alone when no location is chosen" do
      stock_at(kitchen, 8)
      stock_at(branch, 4)

      overall = ::Inventory::IngredientBalanceHistoryService.new(ingredient: ingredient, days: 7).call

      expect(overall.values.last).to eq(ingredient.quantity_on_hand.to_f)
    end

    it "names the series after the location so a filtered chart cannot be misread" do
      stock_at(branch, 4)

      get admin_inventory_ingredient_path(ingredient, chart_location_id: branch.id)

      expect(response.body).to include(
        I18n.t("inventory.ingredients.show.balance_history.series_balance_at",
          location: "Branch A", unit: unit_label)
      )
      expect(response.body).to include(I18n.t("inventory.ingredients.show.balance_history.location_note"))
    end

    it "ignores a location id that is not a stock location" do
      stock_at(kitchen, 8)

      get admin_inventory_ingredient_path(ingredient, chart_location_id: SecureRandom.uuid)

      expect(response).to have_http_status(:ok)
      # Falls back to the company-wide series rather than an empty chart.
      expect(response.body).to include(
        I18n.t("inventory.ingredients.show.balance_history.series_balance", unit: unit_label)
      )
    end

    # Price is the same wherever the stock sits, so the filter must not touch it.
    it "keeps the price line company-wide" do
      stock_at(branch, 4)
      price(1_000, on: Date.current - 3)

      get admin_inventory_ingredient_path(ingredient, chart_location_id: branch.id)

      expect(response.body).to include(I18n.t("inventory.ingredients.show.balance_history.series_price"))
    end
  end
end
