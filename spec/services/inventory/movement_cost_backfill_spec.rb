# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::MovementCostBackfill do
  let(:location) { create(:location, :central_kitchen) }
  let(:ingredient) { create(:ingredient, quantity_on_hand: 0, cost_per_unit_cents: 999) }
  let(:user) { create(:user, :owner, company: Current.company) }

  # A movement as it looked before costs were stored.
  def legacy(delta, type, at:, batch: nil, transfer: nil)
    adj = StockAdjustment.create!(ingredient: ingredient, user: user, location: location, stock_batch: batch,
      stock_transfer: transfer, quantity_delta: delta, adjustment_type: type)
    adj.update_columns(unit_cost_cents: nil, unit_cost_estimated: false, created_at: at)
    adj
  end

  def batch(qty, cost, reference: nil)
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: qty,
      quantity_remaining: qty, cost_per_unit_cents: cost, received_on: Date.current, batch_reference: reference)
  end

  it "costs a batch-linked movement at its batch, exactly" do
    receipt = legacy(10, "vendor_invoice", at: 3.days.ago, batch: batch(10, 450))

    described_class.call

    expect(receipt.reload).to have_attributes(unit_cost_cents: 450, unit_cost_estimated: false)
  end

  it "costs a manual add from the ADJ batch it created for itself" do
    add = legacy(5, "manual_add", at: 3.days.ago)
    batch(5, 320, reference: "ADJ-#{add.id}")

    described_class.call

    expect(add.reload).to have_attributes(unit_cost_cents: 320, unit_cost_estimated: false)
  end

  # The case found in SAQR's data: free seed stock written off by a stock take
  # was priced at today's cost and came out in the billions. Replaying the
  # ledger prices the write-off at the average it was actually taken from.
  it "prices an uncosted removal at the running average of the time, not today's" do
    seed = legacy(100, "manual_add", at: 5.days.ago)
    batch(100, 0, reference: "ADJ-#{seed.id}")
    legacy(100, "vendor_invoice", at: 4.days.ago, batch: batch(100, 200))
    write_off = legacy(-100, "cycle_count_correction", at: 3.days.ago)

    described_class.call

    # (100 x 0 + 100 x 200) / 200
    expect(write_off.reload).to have_attributes(unit_cost_cents: 100, unit_cost_estimated: true)
  end

  it "carries the last average through a negative balance and resets on the next receipt" do
    legacy(10, "vendor_invoice", at: 5.days.ago, batch: batch(10, 300))
    first = legacy(-15, "consumption", at: 4.days.ago)
    while_negative = legacy(-5, "consumption", at: 3.days.ago)
    legacy(20, "vendor_invoice", at: 2.days.ago, batch: batch(20, 500))
    after = legacy(-2, "consumption", at: 1.day.ago)

    described_class.call

    expect(first.reload.unit_cost_cents).to eq(300)
    expect(while_negative.reload.unit_cost_cents).to eq(300)
    expect(after.reload.unit_cost_cents).to eq(500)
  end

  it "is repeatable: a second run gives the same costs" do
    legacy(10, "vendor_invoice", at: 2.days.ago, batch: batch(10, 300))
    removal = legacy(-4, "consumption", at: 1.day.ago)

    described_class.call
    expect { described_class.call }.not_to(change { removal.reload.unit_cost_cents })
  end
end
