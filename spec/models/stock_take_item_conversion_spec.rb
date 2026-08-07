# frozen_string_literal: true

require "rails_helper"

RSpec.describe StockTakeItem, type: :model do
  let(:category) { IngredientCategory.create!(name: "Oils", position: 1, company: Current.company) }
  let(:oil) do
    ing = Ingredient.create!(name: "Oil", ingredient_category: category, unit: "ml",
      reorder_threshold: 1, cost_per_unit_cents: 2, quantity_on_hand: 1000, company: Current.company)
    ing.ingredient_units.create!(unit: "liters", base_units_per_unit: 1000, company: Current.company)
    ing
  end
  let(:location) { create(:location, :central_kitchen) }
  let(:stock_take) { StockTake.create!(user: create(:user), location: location, status: "in_progress", started_at: Time.current) }

  it "computes variance in the base unit when counted in an alternate unit" do
    item = stock_take.stock_take_items.create!(ingredient: oil, expected_quantity: 1000,
      counted_quantity: 1.2, counted_unit: "liters")
    item.calculate_variance!
    # 1.2 L = 1200 ml counted, expected 1000 ml → +200 ml
    expect(item.variance).to eq(200)
  end

  it "treats a blank counted unit as the base unit" do
    item = stock_take.stock_take_items.create!(ingredient: oil, expected_quantity: 1000, counted_quantity: 900)
    item.calculate_variance!
    expect(item.variance).to eq(-100)
  end

  it "values counted and variance amounts with location WAC" do
    StockBatch.create!(
      ingredient: oil,
      location: location,
      quantity_received: 1000,
      quantity_remaining: 1000,
      cost_per_unit_cents: 5,
      received_on: Date.current
    )
    # Master cost is 2; WAC is 5 — values must use WAC.
    item = stock_take.stock_take_items.create!(ingredient: oil, expected_quantity: 1000,
      counted_quantity: 800)
    item.calculate_variance!
    item.save!

    expect(item.unit_cost_cents).to eq(5)
    expect(item.counted_value_cents).to eq(4000) # 800 * 5
    expect(item.variance_value_cents).to eq(-1000) # -200 * 5
  end
end
