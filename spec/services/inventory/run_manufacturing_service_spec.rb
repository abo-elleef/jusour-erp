# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::RunManufacturingService do
  let(:user) { create(:user) }
  let(:category) { IngredientCategory.create!(name: "Proteins", position: 1, company: Current.company) }

  let(:chicken) do
    Ingredient.create!(
      name: "Chicken Thighs Test",
      ingredient_category: category,
      unit: "kg",
      reorder_threshold: 5,
      cost_per_unit_cents: 450,
      quantity_on_hand: 10
    )
  end

  let(:buttermilk) do
    Ingredient.create!(
      name: "Buttermilk Test",
      ingredient_category: category,
      unit: "liters",
      reorder_threshold: 3,
      cost_per_unit_cents: 150,
      quantity_on_hand: 8
    )
  end

  let(:marinated) do
    Ingredient.create!(
      name: "Marinated Chicken Test",
      ingredient_category: category,
      unit: "kg",
      reorder_threshold: 2,
      cost_per_unit_cents: 0,
      quantity_on_hand: 0
    )
  end

  let(:template) do
    template = ManufacturingTemplate.create!(
      name: "Marinate Chicken Batch",
      output_ingredient: marinated,
      yield_quantity: 5,
      active: false
    )
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: chicken, quantity_used: 4)
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: buttermilk, quantity_used: 2)
    template.update!(active: true)
    template
  end

  before do
    [chicken, buttermilk].each do |ingredient|
      StockBatch.create!(
        ingredient: ingredient,
        quantity_received: ingredient.quantity_on_hand,
        quantity_remaining: ingredient.quantity_on_hand,
        cost_per_unit_cents: ingredient.cost_per_unit_cents,
        received_on: Date.current
      )
    end
  end

  describe "#call" do
    it "deducts inputs and adds output for multiple runs" do
      described_class.new(
        template: template,
        user: user,
        runs_count: 2,
        occurred_on: Date.current
      ).call

      expect(chicken.reload.quantity_on_hand.to_d).to eq(2) # 10 - (4 * 2)
      expect(buttermilk.reload.quantity_on_hand.to_d).to eq(4) # 8 - (2 * 2)
      expect(marinated.reload.quantity_on_hand.to_d).to eq(10) # 5 * 2

      expect(ManufacturingRun.count).to eq(1)
      expect(StockAdjustment.where(adjustment_type: "production_consumption").count).to eq(2)
      expect(StockAdjustment.where(adjustment_type: "production_output").count).to eq(1)

      output_batch = marinated.stock_batches.last
      expect(output_batch.quantity_remaining.to_d).to eq(10)
      expected_cost = (((4 * 2 * 450) + (2 * 2 * 150)).to_d / 10).round
      expect(output_batch.cost_per_unit_cents).to eq(expected_cost)
    end

    it "allows run when input stock is below required" do
      chicken.update!(quantity_on_hand: 1)
      chicken.stock_batches.update_all(quantity_remaining: 1)

      described_class.new(
        template: template,
        user: user,
        runs_count: 1
      ).call

      expect(chicken.reload.quantity_on_hand.to_d).to eq(-3)
      expect(marinated.reload.quantity_on_hand.to_d).to eq(5)
    end
  end
end
