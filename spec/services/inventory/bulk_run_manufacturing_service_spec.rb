# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::BulkRunManufacturingService do
  let(:user) { create(:user) }
  let(:category) { IngredientCategory.create!(name: "Bulk Mfg", position: 1, company: Current.company) }
  let(:kitchen) { create(:location, :central_kitchen) }

  def ingredient(name, on_hand: 20)
    Ingredient.create!(
      name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: on_hand
    )
  end

  def stock_at!(ing, qty)
    ing.ingredient_locations.create!(location: kitchen, quantity_on_hand: qty, reorder_threshold: 0)
    StockBatch.create!(
      ingredient: ing, location: kitchen,
      quantity_received: qty, quantity_remaining: qty,
      cost_per_unit_cents: 100, received_on: Date.current
    )
  end

  def template_for(name, input:, output:, qty: 1, yield_qty: 2)
    template = ManufacturingTemplate.create!(
      name: name, output_ingredient: output, yield_quantity: yield_qty, active: false
    )
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: input, quantity_used: qty)
    template.update!(active: true)
    template
  end

  let(:flour) { ingredient("Bulk Flour") }
  let(:dough) { ingredient("Bulk Dough", on_hand: 0) }
  let(:sauce_in) { ingredient("Bulk Tomato") }
  let(:sauce_out) { ingredient("Bulk Sauce", on_hand: 0) }
  let(:dough_template) { template_for("Make dough", input: flour, output: dough) }
  let(:sauce_template) { template_for("Make sauce", input: sauce_in, output: sauce_out) }

  before do
    stock_at!(flour, 20)
    stock_at!(sauce_in, 20)
  end

  it "records only rows with a quantity and skips blanks" do
    runs = described_class.new(
      user: user, location: kitchen, occurred_on: Date.current,
      rows: [
        { "template_id" => dough_template.id, "runs_count" => "2", "shelf_life_days" => "4" },
        { "template_id" => sauce_template.id, "runs_count" => "", "shelf_life_days" => "4" }
      ]
    ).call

    expect(runs.size).to eq(1)
    expect(runs.first.manufacturing_template).to eq(dough_template)
    expect(runs.first.runs_count.to_d).to eq(2)
    expect(dough.reload.quantity_on_hand.to_d).to eq(4)
    expect(sauce_out.reload.quantity_on_hand.to_d).to eq(0)
  end

  it "rolls back every run when a later row is invalid" do
    expect {
      described_class.new(
        user: user, location: kitchen, occurred_on: Date.current,
        rows: [
          { "template_id" => dough_template.id, "runs_count" => "1", "shelf_life_days" => "4" },
          { "template_id" => sauce_template.id, "runs_count" => "1", "shelf_life_days" => "0" }
        ]
      ).call
    }.to raise_error(Inventory::RunManufacturingService::Error)

    expect(ManufacturingRun.count).to eq(0)
    expect(dough.reload.quantity_on_hand.to_d).to eq(0)
    expect(sauce_out.reload.quantity_on_hand.to_d).to eq(0)
  end

  it "requires at least one filled row and a location" do
    expect {
      described_class.new(user: user, location: nil, occurred_on: Date.current, rows: []).call
    }.to raise_error(Inventory::BulkRunManufacturingService::Error, I18n.t("production.location_required"))

    expect {
      described_class.new(
        user: user, location: kitchen, occurred_on: Date.current,
        rows: [{ "template_id" => dough_template.id, "runs_count" => "" }]
      ).call
    }.to raise_error(Inventory::BulkRunManufacturingService::Error, I18n.t("production.bulk.none_filled"))
  end
end
