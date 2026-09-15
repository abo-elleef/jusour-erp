# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::SyncManufacturedCostService do
  let(:company) { Current.company }
  let(:category) { IngredientCategory.create!(name: "Prep", position: 1, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:other_location) { create(:location, company: company) }

  let(:flour) do
    Ingredient.create!(name: "Flour Test", ingredient_category: category, unit: "kg",
      cost_per_unit_cents: 80, quantity_on_hand: 100)
  end

  # A manufacturing template output, marked derived — the shape the migration
  # backfills for zero-cost outputs.
  let(:dough) do
    Ingredient.create!(name: "Dough Test", ingredient_category: category, unit: "kg",
      cost_per_unit_cents: 0, cost_source: "derived", quantity_on_hand: 0)
  end

  def build_template(output)
    template = ManufacturingTemplate.create!(name: "Make #{output.name}", output_ingredient: output,
      yield_quantity: 5, active: false)
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: flour, quantity_used: 4)
    template.update!(active: true)
    template
  end

  def create_batch(ingredient, qty:, cost:, loc: kitchen)
    StockBatch.create!(ingredient: ingredient, location: loc, quantity_received: qty,
      quantity_remaining: qty, cost_per_unit_cents: cost, received_on: Date.current)
  end

  before { build_template(dough) }

  describe "the derived cost" do
    it "is the weighted average of the remaining batches" do
      create_batch(dough, qty: 2, cost: 100)  # value 200
      create_batch(dough, qty: 6, cost: 200)  # value 1200
      # WAC = 1400 / 8 = 175

      result = described_class.call(ingredient: dough)

      expect(result).to be_changed
      expect(result.previous_cents).to eq(0)
      expect(result.new_cents).to eq(175)
      expect(dough.reload.cost_per_unit_cents).to eq(175)
      expect(dough.cost_synced_at).to be_present
    end

    it "spans every location, unlike LocationUnitCost" do
      create_batch(dough, qty: 5, cost: 100, loc: kitchen)
      create_batch(dough, qty: 5, cost: 300, loc: other_location)

      expect(described_class.call(ingredient: dough).new_cents).to eq(200)
    end

    it "ignores batches that have been fully drawn down" do
      create_batch(dough, qty: 10, cost: 900).update!(quantity_remaining: 0)
      create_batch(dough, qty: 4, cost: 250)

      expect(described_class.call(ingredient: dough).new_cents).to eq(250)
    end
  end

  describe "when it must not write" do
    it "keeps the last known cost when no batch has stock left" do
      dough.update!(cost_per_unit_cents: 500)
      create_batch(dough, qty: 3, cost: 900).update!(quantity_remaining: 0)

      result = described_class.call(ingredient: dough)

      expect(result.skipped_reason).to eq(:no_batches)
      expect(dough.reload.cost_per_unit_cents).to eq(500)
    end

    it "leaves a manually owned cost alone" do
      dough.update!(cost_source: "manual", cost_per_unit_cents: 3000)
      create_batch(dough, qty: 10, cost: 570)

      result = described_class.call(ingredient: dough)

      expect(result.skipped_reason).to eq(:manual_cost)
      expect(dough.reload.cost_per_unit_cents).to eq(3000)
    end

    it "leaves a purchased ingredient alone even if it is somehow marked derived" do
      flour.update!(cost_source: "derived")
      create_batch(flour, qty: 10, cost: 999)

      result = described_class.call(ingredient: flour)

      expect(result.skipped_reason).to eq(:not_manufactured)
      expect(flour.reload.cost_per_unit_cents).to eq(80)
    end

    it "does not touch the record when the average has not moved" do
      create_batch(dough, qty: 4, cost: 250)
      described_class.call(ingredient: dough)
      synced_at = dough.reload.cost_synced_at

      result = described_class.call(ingredient: dough.reload)

      expect(result.skipped_reason).to eq(:unchanged)
      expect(dough.reload.cost_synced_at).to eq(synced_at)
    end
  end

  describe ".call_for_company" do
    let(:sauce) do
      Ingredient.create!(name: "Sauce Test", ingredient_category: category, unit: "liters",
        cost_per_unit_cents: 0, cost_source: "derived", quantity_on_hand: 0)
    end

    before { build_template(sauce) }

    it "syncs every derived output and reports only the ones that moved" do
      create_batch(dough, qty: 4, cost: 250)
      create_batch(sauce, qty: 2, cost: 600)

      results = described_class.call_for_company

      expect(results.select(&:changed?).map(&:new_cents)).to contain_exactly(250, 600)
      expect(dough.reload.cost_per_unit_cents).to eq(250)
      expect(sauce.reload.cost_per_unit_cents).to eq(600)
    end

    it "resolves many ingredients without querying batches per ingredient" do
      create_batch(dough, qty: 4, cost: 250)
      create_batch(sauce, qty: 2, cost: 600)

      batch_queries = 0
      counter = lambda do |_n, _s, _f, _i, payload|
        batch_queries += 1 if payload[:sql].include?("stock_batches") && !payload[:name].to_s.include?("SCHEMA")
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.call_for_company
      end

      expect(batch_queries).to eq(1)
    end
  end
end
