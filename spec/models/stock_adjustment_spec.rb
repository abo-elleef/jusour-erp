# frozen_string_literal: true

require "rails_helper"

RSpec.describe StockAdjustment, type: :model do
  let(:category) { create(:ingredient_category) }
  let(:location) { create(:location, :central_kitchen) }
  let(:ingredient) { create(:ingredient, ingredient_category: category, quantity_on_hand: 0, cost_per_unit_cents: 500) }
  let(:user) { create(:user, :owner, company: Current.company) }

  def adjust(delta, maintain_batches: true, loc: location, type: "manual_add")
    StockAdjustment.create!(ingredient: ingredient, user: user, location: loc,
      quantity_delta: delta, adjustment_type: type, maintain_batches: maintain_batches)
  end

  describe "batch maintenance for manual adjustments" do
    it "creates a location batch on a manual add, costed at the ingredient's current cost" do
      expect { adjust(10) }.to change { ingredient.stock_batches.where(location: location).count }.by(1)

      batch = ingredient.stock_batches.where(location: location).last
      expect(batch.quantity_remaining).to eq(10)
      expect(batch.cost_per_unit_cents).to eq(500)
    end

    it "uses batch_cost_per_unit_cents when provided for an overage" do
      StockAdjustment.create!(
        ingredient: ingredient,
        user: user,
        location: location,
        quantity_delta: 3,
        adjustment_type: "cycle_count_correction",
        maintain_batches: true,
        batch_cost_per_unit_cents: 175
      )

      batch = ingredient.stock_batches.where(location: location).last
      expect(batch.cost_per_unit_cents).to eq(175)
    end

    it "draws down existing batches oldest-first on a manual removal" do
      adjust(10)
      adjust(-4)
      expect(ingredient.stock_batches.where(location: location).sum(:quantity_remaining)).to eq(6)
    end

    it "leaves batches untouched when maintain_batches is false (service flows)" do
      expect { adjust(10, maintain_batches: false) }.not_to change(StockBatch, :count)
    end

    it "does nothing without a location (nothing to attach a batch to)" do
      expect { adjust(10, loc: nil) }.not_to change(StockBatch, :count)
    end
  end

  describe "unit cost stamping" do
    def batch!(qty, cost)
      StockBatch.create!(ingredient: ingredient, location: location, quantity_received: qty,
        quantity_remaining: qty, cost_per_unit_cents: cost, received_on: Date.current)
    end

    it "records a removal at the location's weighted average before it draws batches down" do
      batch!(10, 100)
      batch!(10, 300)

      removal = adjust(-10, type: "manual_remove")

      # FIFO empties the 100 batch, so reading after the draw-down would say 300.
      expect(removal.reload.unit_cost_cents).to eq(200)
      expect(removal.unit_cost_estimated).to be(false)
    end

    it "costs a manual add's batch at the location average, so batch and movement agree" do
      batch!(10, 100)
      batch!(10, 300)

      add = adjust(5)

      expect(add.reload.unit_cost_cents).to eq(200)
      expect(ingredient.stock_batches.find_by(batch_reference: "ADJ-#{add.id}").cost_per_unit_cents).to eq(200)
    end

    it "records a movement tied to a batch at that batch's cost" do
      batch!(10, 100)
      receipt_batch = batch!(5, 900)

      movement = StockAdjustment.create!(ingredient: ingredient, user: user, location: location,
        stock_batch: receipt_batch, quantity_delta: 5, adjustment_type: "vendor_invoice")

      expect(movement.reload.unit_cost_cents).to eq(900)
    end

    it "uses the overage batch cost when one is given" do
      batch!(10, 100)

      movement = StockAdjustment.create!(ingredient: ingredient, user: user, location: location,
        quantity_delta: 3, adjustment_type: "cycle_count_correction",
        maintain_batches: true, batch_cost_per_unit_cents: 175)

      expect(movement.reload.unit_cost_cents).to eq(175)
    end

    it "keeps a cost the caller passed in" do
      batch!(10, 100)

      movement = StockAdjustment.create!(ingredient: ingredient, user: user, location: location,
        quantity_delta: -2, unit_cost_cents: 444, adjustment_type: "consumption")

      expect(movement.reload.unit_cost_cents).to eq(444)
    end

    it "falls back to the ingredient's standard cost without a location" do
      expect(adjust(4, loc: nil).reload.unit_cost_cents).to eq(500)
    end
  end
end
