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
end
