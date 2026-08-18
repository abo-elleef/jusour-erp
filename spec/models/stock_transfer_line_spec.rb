# frozen_string_literal: true

require "rails_helper"

RSpec.describe StockTransferLine, type: :model do
  let(:company) { create(:company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 10.0) }

  before { Current.company = company }

  def build_line(requested:, on_hand:, batches:)
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: on_hand)
    StockBatch.create!(
      ingredient: ingredient, location: kitchen,
      quantity_received: batches, quantity_remaining: batches,
      cost_per_unit_cents: 100, received_on: Date.current
    ) if batches.positive?
    transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient, quantity_requested: requested)
  end

  it "is short when pending send is greater than transferable source stock" do
    line = build_line(requested: 8, on_hand: 2, batches: 2)
    expect(line.short_at_source?).to be(true)
  end

  it "is not short when source covers the pending send" do
    line = build_line(requested: 4, on_hand: 10, batches: 10)
    expect(line.short_at_source?).to be(false)
  end

  it "is not short after the pending send is fulfilled" do
    line = build_line(requested: 8, on_hand: 2, batches: 2)
    line.update!(quantity_sent: 8)
    expect(line.short_at_source?).to be(false)
  end

  it "is source-on-hand short when source quantity is negative" do
    line = build_line(requested: 8, on_hand: -6, batches: 0)
    expect(line.source_on_hand_short?).to be(true)
  end

  it "is not source-on-hand short when source quantity is zero or positive" do
    line = build_line(requested: 4, on_hand: 0, batches: 0)
    expect(line.source_on_hand_short?).to be(false)
  end

  it "recommends max(0, order_limit - counted_quantity)" do
    transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
    line = create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient,
                  quantity_requested: 5, order_limit: 20, counted_quantity: 6)
    expect(line.recommended_quantity).to eq(14)
  end

  it "recommends zero when counted is above the limit" do
    transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
    line = create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient,
                  quantity_requested: 1, order_limit: 10, counted_quantity: 12)
    expect(line.recommended_quantity).to eq(0)
  end

  it "has no recommendation until both limit and count are present" do
    transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
    line = create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient, quantity_requested: 1, order_limit: 10)
    expect(line.recommended_quantity).to be_nil
  end
end
