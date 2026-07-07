# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Recipes in an alternate unit", type: :model do
  let(:category) { IngredientCategory.create!(name: "Oils", position: 1, company: Current.company) }
  let(:oil) do
    ing = Ingredient.create!(name: "Oil", ingredient_category: category, unit: "ml",
      reorder_threshold: 1, cost_per_unit_cents: 2, quantity_on_hand: 0, company: Current.company)
    ing.ingredient_units.create!(unit: "liters", base_units_per_unit: 1000, company: Current.company)
    ing
  end
  let(:menu_item) { create(:menu_item) }

  describe "Recipe#base_quantity_used" do
    it "converts the recipe unit to the base unit" do
      recipe = Recipe.create!(menu_item: menu_item, ingredient: oil, quantity_used: 0.25, unit: "liters")
      expect(recipe.base_quantity_used).to eq(250) # 0.25 L = 250 ml
    end

    it "treats a blank unit as the base unit" do
      recipe = Recipe.create!(menu_item: menu_item, ingredient: oil, quantity_used: 250)
      expect(recipe.base_quantity_used).to eq(250)
    end

    it "rejects a unit the ingredient doesn't support" do
      recipe = Recipe.new(menu_item: menu_item, ingredient: oil, quantity_used: 1, unit: "gallons")
      expect(recipe).not_to be_valid
    end
  end

  describe "stock deduction uses base units" do
    let(:location) { create(:location, company: Current.company) }

    it "deducts the base-unit quantity from stock" do
      oil.update!(quantity_on_hand: 1000)
      StockBatch.create!(ingredient: oil, location: location, quantity_received: 1000,
        quantity_remaining: 1000, cost_per_unit_cents: 2, received_on: Date.current)
      Recipe.create!(menu_item: menu_item, ingredient: oil, quantity_used: 0.25, unit: "liters") # 250 ml

      order = create(:order, status: "submitted", location: location, order_type: "table")
      create(:order_item, order: order, menu_item: menu_item, quantity: 2)

      Inventory::DeductStockService.new(order).call

      # 2 units × 250 ml = 500 ml deducted from 1000
      expect(oil.stock_batches.sum(:quantity_remaining).to_d).to eq(500)
    end
  end
end
