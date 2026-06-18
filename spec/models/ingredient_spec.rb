# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ingredient, type: :model do
  let(:category) { IngredientCategory.create!(name: "Test Cat", company: Current.company) }

  it "is valid with defaults" do
    expect(described_class.new(
      name: "Test Ingredient",
      ingredient_category: category,
      unit: "kg",
      reorder_threshold: 1,
      quantity_on_hand: 5,
      cost_per_unit_cents: 100
    )).to be_valid
  end

  it "detects low stock" do
    ingredient = described_class.create!(
      name: "Low Item",
      ingredient_category: category,
      unit: "kg",
      reorder_threshold: 10,
      quantity_on_hand: 5,
      cost_per_unit_cents: 100
    )
    expect(ingredient).to be_low_stock
  end

  it "validates shelf_life_days when present" do
    ingredient = described_class.new(
      name: "Perishable",
      ingredient_category: category,
      unit: "kg",
      shelf_life_days: 0
    )
    expect(ingredient).not_to be_valid
    expect(ingredient.errors[:shelf_life_days]).to be_present
  end
end
