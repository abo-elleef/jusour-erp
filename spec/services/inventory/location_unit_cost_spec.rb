# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::LocationUnitCost do
  let(:company) { create(:company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let(:other_location) { create(:location, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 0, cost_per_unit_cents: 100)
  end

  before { Current.company = company }

  def create_batch(qty:, cost:, loc: location)
    StockBatch.create!(
      ingredient: ingredient,
      location: loc,
      quantity_received: qty,
      quantity_remaining: qty,
      cost_per_unit_cents: cost,
      received_on: Date.current
    )
  end

  it "returns the weighted average of remaining batches at the location" do
    create_batch(qty: 2, cost: 100) # value 200
    create_batch(qty: 6, cost: 200) # value 1200
    # WAC = 1400 / 8 = 175

    expect(described_class.call(ingredient: ingredient, location: location)).to eq(175)
  end

  it "ignores batches at other locations" do
    create_batch(qty: 10, cost: 500, loc: other_location)
    create_batch(qty: 4, cost: 100)

    expect(described_class.call(ingredient: ingredient, location: location)).to eq(100)
  end

  it "falls back to the latest supplier price when there is no location stock" do
    supplier = Supplier.create!(name: "Fresh Farms", company: company)
    SupplierPriceHistory.create!(
      supplier: supplier,
      ingredient: ingredient,
      price_cents: 250,
      effective_date: Date.current - 2,
      recorded_by_user: create(:user, company: company)
    )
    SupplierPriceHistory.create!(
      supplier: supplier,
      ingredient: ingredient,
      price_cents: 333,
      effective_date: Date.current,
      recorded_by_user: create(:user, company: company)
    )

    expect(described_class.call(ingredient: ingredient, location: location)).to eq(333)
  end

  it "falls back to the ingredient master cost when no batches or history exist" do
    expect(described_class.call(ingredient: ingredient, location: location)).to eq(100)
  end

  it "builds a map for many ingredients in one pass" do
    other = create(:ingredient, company: company, ingredient_category: category, cost_per_unit_cents: 50)
    create_batch(qty: 1, cost: 400)

    map = described_class.map_for(ingredients: [ingredient, other], location: location)
    expect(map[ingredient.id]).to eq(400)
    expect(map[other.id]).to eq(50)
  end
end
