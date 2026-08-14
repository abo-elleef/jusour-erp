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

  let(:kitchen) { create(:location, :central_kitchen) }

  before do
    [chicken, buttermilk].each do |ingredient|
      ingredient.ingredient_locations.create!(location: kitchen, quantity_on_hand: ingredient.quantity_on_hand, reorder_threshold: 0)
      StockBatch.create!(
        ingredient: ingredient,
        location: kitchen,
        quantity_received: ingredient.quantity_on_hand,
        quantity_remaining: ingredient.quantity_on_hand,
        cost_per_unit_cents: ingredient.cost_per_unit_cents,
        received_on: Date.current
      )
    end
  end

  describe "#call" do
    it "deducts inputs and adds output at the production location for multiple runs" do
      described_class.new(
        template: template,
        user: user,
        location: kitchen,
        runs_count: 2,
        shelf_life_days: 5,
        occurred_on: Date.current
      ).call

      expect(chicken.reload.quantity_on_hand.to_d).to eq(2) # 10 - (4 * 2)
      expect(buttermilk.reload.quantity_on_hand.to_d).to eq(4) # 8 - (2 * 2)
      expect(marinated.reload.quantity_on_hand.to_d).to eq(10) # 5 * 2

      # Inputs drawn down from the kitchen's own batches.
      expect(chicken.stock_batches.where(location: kitchen).sum(:quantity_remaining).to_d).to eq(2)

      expect(ManufacturingRun.count).to eq(1)
      expect(ManufacturingRun.last.location).to eq(kitchen)

      output_batch = marinated.stock_batches.last
      expect(output_batch.location).to eq(kitchen)
      expect(output_batch.quantity_remaining.to_d).to eq(10)
      expect(output_batch.expires_on).to eq(Date.current + 5.days)
      expected_cost = (((4 * 2 * 450) + (2 * 2 * 150)).to_d / 10).round
      expect(output_batch.cost_per_unit_cents).to eq(expected_cost)

      # Output landed in the kitchen's on-hand, so it's transferable from there.
      expect(kitchen.ingredient_stock(marinated).quantity_on_hand.to_d).to eq(10)

      run = ManufacturingRun.last
      expect(run.shelf_life_days).to eq(5)
      expect(run.output_expires_on).to eq(Date.current + 5.days)
    end

    it "allows a run when input stock is below required" do
      chicken.ingredient_locations.find_by(location: kitchen).update!(quantity_on_hand: 1)
      chicken.stock_batches.update_all(quantity_remaining: 1)

      described_class.new(
        template: template, user: user, location: kitchen,
        runs_count: 1, shelf_life_days: 3
      ).call

      expect(chicken.reload.quantity_on_hand.to_d).to eq(-3)
      expect(marinated.reload.quantity_on_hand.to_d).to eq(5)
    end

    it "rejects zero shelf life" do
      expect {
        described_class.new(
          template: template, user: user, location: kitchen,
          runs_count: 1, shelf_life_days: 0
        ).call
      }.to raise_error(Inventory::RunManufacturingService::Error, I18n.t("production.invalid_shelf_life"))
    end

    it "requires a production location" do
      expect {
        described_class.new(
          template: template, user: user, location: nil,
          runs_count: 1, shelf_life_days: 3
        ).call
      }.to raise_error(Inventory::RunManufacturingService::Error, I18n.t("production.location_required"))
    end
  end

  describe "#call (main-ingredient-controlled)" do
    before { template.update!(control_mode: "main_ingredient", main_ingredient_id: chicken.id) }

    it "derives the batch count from the main-ingredient amount and scales everything proportionally" do
      # Chicken is 4 per batch; feeding 12 implies 3 batches.
      run = described_class.new(
        template: template, user: user, location: kitchen,
        main_input_quantity: 12, shelf_life_days: 5
      ).call

      expect(run.runs_count.to_d).to eq(3)
      expect(chicken.reload.quantity_on_hand.to_d).to eq(-2)  # 10 - (4 * 3)
      expect(buttermilk.reload.quantity_on_hand.to_d).to eq(2) # 8 - (2 * 3)
      expect(marinated.reload.quantity_on_hand.to_d).to eq(15) # 5 * 3
    end

    it "records the entered main amount and unit on the run" do
      run = described_class.new(
        template: template, user: user, location: kitchen,
        main_input_quantity: 8, main_input_unit: "kg", shelf_life_days: 5
      ).call

      expect(run.main_ingredient_driven?).to be(true)
      expect(run.main_input_quantity.to_d).to eq(8)
      expect(run.main_input_unit).to eq("kg")
    end

    it "converts an alternate main-ingredient unit before deriving the batch count" do
      # Chicken's base unit is kg; add grams as an alternate (1 g = 0.001 kg).
      chicken.ingredient_units.create!(unit: "g", base_units_per_unit: 0.001, company: Current.company)

      # 12000 g = 12 kg base = 3 batches (chicken is 4 kg per batch).
      run = described_class.new(
        template: template, user: user, location: kitchen,
        main_input_quantity: 12_000, main_input_unit: "g", shelf_life_days: 5
      ).call

      expect(run.runs_count.to_d).to eq(3)
      expect(marinated.reload.quantity_on_hand.to_d).to eq(15)
    end

    it "rejects a zero or blank main-ingredient amount" do
      expect {
        described_class.new(
          template: template, user: user, location: kitchen,
          main_input_quantity: 0, shelf_life_days: 5
        ).call
      }.to raise_error(Inventory::RunManufacturingService::Error, I18n.t("production.invalid_main_quantity"))

      expect(ManufacturingRun.count).to eq(0)
    end
  end
end
