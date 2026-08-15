# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::LocationBalanceHistoryService do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { Current.company }
  let(:user) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:flour) { create(:ingredient, company: company, ingredient_category: category, name: "Flour", quantity_on_hand: 0) }
  let(:oil) { create(:ingredient, company: company, ingredient_category: category, name: "Oil", quantity_on_hand: 0) }

  before do
    IngredientLocation.create!(ingredient: flour, location: location, quantity_on_hand: 0, reorder_threshold: 1)
    IngredientLocation.create!(ingredient: oil, location: location, quantity_on_hand: 0, reorder_threshold: 1)
  end

  def adjust!(ingredient, delta)
    StockAdjustment.create!(
      ingredient: ingredient,
      user: user,
      location: location,
      quantity_delta: delta,
      adjustment_type: "manual_add",
      reason_notes: "test",
      maintain_batches: true
    )
  end

  it "returns multi-series daily closing balances for selected ingredients" do
    travel_to Time.zone.local(2026, 8, 10, 9, 0, 0)
    adjust!(flour, 10)

    travel_to Time.zone.local(2026, 8, 11, 9, 0, 0)
    adjust!(oil, 4)

    travel_to Time.zone.local(2026, 8, 12, 9, 0, 0)
    adjust!(flour, -3)

    travel_to Time.zone.local(2026, 8, 15, 12, 0, 0)
    series = described_class.new(
      location: location,
      ingredient_ids: [flour.id, oil.id],
      days: 30,
      as_of: Date.new(2026, 8, 15)
    ).call

    expect(series.map { |s| s[:name] }).to eq(%w[Flour Oil])
    flour_data = series.find { |s| s[:name] == "Flour" }[:data]
    oil_data = series.find { |s| s[:name] == "Oil" }[:data]

    expect(flour_data["2026-08-09"]).to eq(0.0)
    expect(flour_data["2026-08-10"]).to eq(10.0)
    expect(flour_data["2026-08-12"]).to eq(7.0)
    expect(flour_data["2026-08-15"]).to eq(7.0)
    expect(oil_data["2026-08-10"]).to eq(0.0)
    expect(oil_data["2026-08-11"]).to eq(4.0)
    expect(oil_data["2026-08-15"]).to eq(4.0)
  ensure
    travel_back
  end

  it "caps the number of compared ingredients" do
    ids = Array.new(described_class::MAX_INGREDIENTS + 2) { flour.id }
    expect(described_class.new(location: location, ingredient_ids: ids).call.size).to be <= 1
  end

  it "returns an empty series list when nothing is selected" do
    expect(described_class.new(location: location, ingredient_ids: []).call).to eq([])
  end
end
