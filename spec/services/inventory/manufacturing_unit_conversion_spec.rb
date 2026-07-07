# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manufacturing with alternate units", type: :model do
  let(:user) { create(:user) }
  let(:location) { create(:location, company: Current.company) }
  let(:category) { IngredientCategory.create!(name: "Bakery", position: 1, company: Current.company) }

  let(:flour) do
    ing = Ingredient.create!(name: "Flour", ingredient_category: category, unit: "g",
      reorder_threshold: 1, cost_per_unit_cents: 1, quantity_on_hand: 100_000, company: Current.company)
    ing.ingredient_units.create!(unit: "kg", base_units_per_unit: 1000, company: Current.company)
    ing
  end

  let(:dough) do
    ing = Ingredient.create!(name: "Dough", ingredient_category: category, unit: "g",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: Current.company)
    ing.ingredient_units.create!(unit: "kg", base_units_per_unit: 1000, company: Current.company)
    ing
  end

  let(:template) do
    t = ManufacturingTemplate.create!(name: "Make Dough", output_ingredient: dough,
      yield_quantity: 2, yield_unit: "kg", active: false, company: Current.company) # 2 kg = 2000 g per run
    ManufacturingTemplateLine.create!(manufacturing_template: t, ingredient: flour,
      quantity_used: 3, unit: "kg") # 3 kg = 3000 g per run
    t.update!(active: true)
    t
  end

  before do
    StockBatch.create!(ingredient: flour, location: location, quantity_received: 100_000,
      quantity_remaining: 100_000, cost_per_unit_cents: 1, received_on: Date.current)
  end

  it "consumes inputs and produces output in base units" do
    Inventory::RunManufacturingService.new(
      template: template, user: user, runs_count: 2, shelf_life_days: 5
    ).call

    # Flour: 3 kg × 2 runs = 6000 g consumed → 100000 - 6000
    expect(flour.stock_batches.sum(:quantity_remaining).to_d).to eq(94_000)

    # Dough output: 2 kg × 2 runs = 4000 g produced
    output_batch = dough.stock_batches.order(:created_at).last
    expect(output_batch.quantity_received.to_d).to eq(4_000)
  end

  it "validates units against the ingredient" do
    line = ManufacturingTemplateLine.new(manufacturing_template: template, ingredient: flour,
      quantity_used: 1, unit: "gallons")
    expect(line).not_to be_valid
  end
end
