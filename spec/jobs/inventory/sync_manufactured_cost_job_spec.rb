# frozen_string_literal: true

require "rails_helper"

# The costing is covered by the service spec. What the job owns is tenancy: it is
# handed a bare id by a background worker with no ambient company, and Ingredient
# reads through a company default scope.
RSpec.describe Inventory::SyncManufacturedCostJob do
  let(:owning_company) { create(:company) }

  # A derived manufactured output in +owning_company+, holding one batch.
  let!(:output) do
    previous = Current.company
    Current.company = owning_company

    category = IngredientCategory.create!(name: "Prep", position: 1, company: owning_company)
    input = Ingredient.create!(name: "Input Job", ingredient_category: category, unit: "kg",
      cost_per_unit_cents: 100, quantity_on_hand: 10)
    ingredient = Ingredient.create!(name: "Output Job", ingredient_category: category, unit: "kg",
      cost_per_unit_cents: 0, cost_source: "derived", quantity_on_hand: 0)

    template = ManufacturingTemplate.create!(name: "Make Output Job",
      output_ingredient: ingredient, yield_quantity: 5, active: false)
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: input, quantity_used: 4)
    template.update!(active: true)

    StockBatch.create!(ingredient: ingredient, location: create(:location, :central_kitchen, company: owning_company),
      quantity_received: 10, quantity_remaining: 10, cost_per_unit_cents: 640, received_on: Date.current)

    ingredient
  ensure
    Current.company = previous
  end

  it "syncs the cost under the ingredient's own company, not the ambient one" do
    expect(Current.company).not_to eq(owning_company)

    described_class.perform_now(output.id)

    expect(output.reload.cost_per_unit_cents).to eq(640)
  end

  it "leaves the ambient company untouched" do
    ambient = Current.company

    described_class.perform_now(output.id)

    expect(Current.company).to eq(ambient)
  end

  it "discards quietly when the ingredient has since been deleted" do
    expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
  end
end
