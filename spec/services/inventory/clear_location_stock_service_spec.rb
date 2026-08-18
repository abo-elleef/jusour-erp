# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ClearLocationStockService do
  let(:company) { Current.company }
  let(:user) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:other_location) { create(:location, company: company, name: "Other Branch") }
  let(:category) { create(:ingredient_category, company: company) }

  def stock_ingredient!(name:, location_qty:, other_qty: 0)
    ingredient = create(:ingredient, company: company, ingredient_category: category, name: name, quantity_on_hand: 0)
    IngredientLocation.create!(
      ingredient: ingredient,
      location: location,
      quantity_on_hand: location_qty,
      reorder_threshold: 1
    )
    if other_qty.positive?
      IngredientLocation.create!(
        ingredient: ingredient,
        location: other_location,
        quantity_on_hand: other_qty,
        reorder_threshold: 1
      )
    end
    ingredient.reload
    ingredient.update_column(:quantity_on_hand, ingredient.ingredient_locations.sum(:quantity_on_hand))
    ingredient
  end

  it "zeros on-hand at the location and writes clear-all-stock adjustments" do
    flour = stock_ingredient!(name: "Flour", location_qty: 10, other_qty: 4)
    oil = stock_ingredient!(name: "Oil", location_qty: 2)

    StockBatch.create!(
      ingredient: flour,
      location: location,
      quantity_received: 10,
      quantity_remaining: 10,
      cost_per_unit_cents: 100,
      received_on: Date.current
    )

    result = described_class.new(location: location, user: user).call

    expect(result.adjusted_count).to eq(2)
    expect(flour.ingredient_locations.find_by!(location: location).quantity_on_hand).to eq(0)
    expect(flour.ingredient_locations.find_by!(location: other_location).quantity_on_hand).to eq(4)
    expect(flour.reload.quantity_on_hand).to eq(4)
    expect(oil.ingredient_locations.find_by!(location: location).quantity_on_hand).to eq(0)
    expect(StockBatch.where(location: location).with_stock).to be_empty

    adjustments = StockAdjustment.where(location: location, adjustment_type: "clear_all_stock")
    expect(adjustments.count).to eq(2)
    expect(adjustments.sum(:quantity_delta)).to eq(-12)
  end

  it "is a no-op when the location already has no positive stock" do
    stock_ingredient!(name: "Empty", location_qty: 0)

    result = described_class.new(location: location, user: user).call

    expect(result.adjusted_count).to eq(0)
    expect(StockAdjustment.where(location: location)).to be_empty
  end
end
