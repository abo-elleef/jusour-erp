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

  describe "changing the base unit (on update)" do
    def fresh_ingredient(quantity_on_hand: 0)
      described_class.create!(name: "Base #{SecureRandom.hex(3)}", ingredient_category: category,
        unit: "kg", reorder_threshold: 1, quantity_on_hand: quantity_on_hand, cost_per_unit_cents: 100)
    end

    it "is allowed when there is no stock or batch history" do
      ingredient = fresh_ingredient(quantity_on_hand: 0)
      ingredient.unit = "g"
      expect(ingredient.save).to be(true)
      expect(ingredient.reload.unit).to eq("g")
    end

    it "is blocked once there is stock on hand" do
      ingredient = fresh_ingredient(quantity_on_hand: 5)
      ingredient.unit = "g"
      expect(ingredient).not_to be_valid
      expect(ingredient.errors[:unit]).to be_present
    end

    it "is blocked once a stock batch exists (even at zero on-hand)" do
      ingredient = fresh_ingredient(quantity_on_hand: 0)
      StockBatch.create!(ingredient: ingredient, quantity_received: 3, quantity_remaining: 0,
        cost_per_unit_cents: 100, received_on: Date.current)
      ingredient.reload.unit = "g"
      expect(ingredient).not_to be_valid
      expect(ingredient.errors[:unit]).to be_present
    end

    it "clears alternate units when the base unit changes (their factors no longer apply)" do
      ingredient = fresh_ingredient(quantity_on_hand: 0)
      ingredient.ingredient_units.create!(unit: "g", base_units_per_unit: 0.001, company: Current.company)

      ingredient.reload.update!(unit: "lbs")

      expect(ingredient.reload.ingredient_units).to be_empty
    end

    it "keeps alternate units when the base unit is unchanged" do
      ingredient = fresh_ingredient(quantity_on_hand: 0)
      ingredient.ingredient_units.create!(unit: "g", base_units_per_unit: 0.001, company: Current.company)

      ingredient.reload.update!(reorder_threshold: 4)

      expect(ingredient.reload.ingredient_units.size).to eq(1)
    end
  end
end
