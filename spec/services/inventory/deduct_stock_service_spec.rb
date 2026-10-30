# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::DeductStockService do
  let(:category) { create(:ingredient_category) }
  let(:branch) { create(:location) }
  let(:user) { create(:user, company: Current.company) }

  let(:cheese) do
    create(:ingredient, ingredient_category: category, unit: "kg", quantity_on_hand: 0, cost_per_unit_cents: 500)
  end

  before do
    cheese.ingredient_locations.create!(location: branch, quantity_on_hand: 10, reorder_threshold: 0)
    StockBatch.create!(ingredient: cheese, location: branch, quantity_received: 10,
      quantity_remaining: 10, cost_per_unit_cents: 500, received_on: Date.current)
  end

  let(:menu_item) do
    mi = create(:menu_item)
    Recipe.create!(menu_item: mi, ingredient: cheese, quantity_used: 2, unit: "kg")
    mi
  end

  it "deducts recipe ingredients from the selling location's stock" do
    order = create(:order, user: user, location: branch)
    create(:order_item, order: order, menu_item: menu_item, quantity: 1)

    described_class.new(order).call

    il = branch.ingredient_stock(cheese)
    expect(il.quantity_on_hand.to_d).to eq(8)                    # 10 - 2
    expect(cheese.reload.quantity_on_hand.to_d).to eq(8)         # global = sum of locations
    expect(cheese.stock_batches.where(location: branch).sum(:quantity_remaining).to_d).to eq(8)
  end

  it "does not touch another location's stock" do
    other = create(:location, :central_kitchen)
    cheese.ingredient_locations.create!(location: other, quantity_on_hand: 5, reorder_threshold: 0)

    order = create(:order, user: user, location: branch)
    create(:order_item, order: order, menu_item: menu_item, quantity: 1)
    described_class.new(order).call

    expect(other.ingredient_stock(cheese).quantity_on_hand.to_d).to eq(5)   # untouched
    expect(cheese.reload.quantity_on_hand.to_d).to eq(13)                   # 8 (branch) + 5 (other)
  end

  it "records the consumption at the location average it was drawn from" do
    StockBatch.create!(ingredient: cheese, location: branch, quantity_received: 10,
      quantity_remaining: 10, cost_per_unit_cents: 1500, received_on: Date.current + 1)
    order = create(:order, user: user, location: branch)
    create(:order_item, order: order, menu_item: menu_item, quantity: 1)

    described_class.new(order).call

    # (10 x 500 + 10 x 1500) / 20, read before FIFO takes 2 from the 500 batch.
    movement = StockAdjustment.where(ingredient: cheese, adjustment_type: "consumption").last
    expect(movement.unit_cost_cents).to eq(1000)
  end
end
