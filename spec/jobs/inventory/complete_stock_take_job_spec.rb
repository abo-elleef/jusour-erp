# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::CompleteStockTakeJob, type: :job do
  let(:company) { create(:company) }
  let(:user) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 0) }

  before { Current.company = company }

  def build_completing_take(counted: 9)
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 0.0)
    take = StockTake.create!(
      company: company,
      user: user,
      location: kitchen,
      status: "completing",
      started_at: Time.current
    )
    item = take.stock_take_items.create!(ingredient: ingredient, expected_quantity: 0)
    item.update!(counted_quantity: counted)
    item.calculate_variance!
    item.save!
    take
  end

  it "applies variances, marks completed, and broadcasts a success toast" do
    take = build_completing_take

    expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).once.with(
      "admin_#{company.id}",
      hash_including(target: "toast-container", locals: hash_including(type: :notice))
    )

    described_class.perform_now(take.id, user.id)

    take.reload
    expect(take.status).to eq("completed")
    expect(take.completed_at).to be_present
    expect(take.stock_take_items.first.adjusted).to eq(true)
    expect(kitchen.ingredient_stock(ingredient).quantity_on_hand.to_d).to eq(9)
  end

  it "prices overage batches at location WAC instead of the ingredient master cost" do
    ingredient.update!(cost_per_unit_cents: 100)
    StockBatch.create!(
      ingredient: ingredient,
      location: kitchen,
      quantity_received: 10,
      quantity_remaining: 10,
      cost_per_unit_cents: 400,
      received_on: Date.current
    )
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 10.0)

    take = StockTake.create!(
      company: company,
      user: user,
      location: kitchen,
      status: "completing",
      started_at: Time.current
    )
    item = take.stock_take_items.create!(ingredient: ingredient, expected_quantity: 10)
    item.update!(counted_quantity: 15)
    item.calculate_variance!
    item.save!

    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)

    described_class.perform_now(take.id, user.id)

    overage = ingredient.stock_batches.where(location: kitchen).order(:created_at).last
    expect(overage.quantity_remaining.to_d).to eq(5)
    expect(overage.cost_per_unit_cents).to eq(400)
  end

  it "no-ops when the take is not completing" do
    take = build_completing_take
    take.update!(status: "in_progress")

    expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)

    described_class.perform_now(take.id, user.id)

    take.reload
    expect(take.status).to eq("in_progress")
    expect(kitchen.ingredient_stock(ingredient).quantity_on_hand.to_d).to eq(0)
  end

  it "marks failed and broadcasts an alert toast when applying variances raises" do
    take = build_completing_take

    allow(StockAdjustment).to receive(:create!).and_raise(StandardError, "boom")

    expect(Turbo::StreamsChannel).to receive(:broadcast_append_to).once.with(
      "admin_#{company.id}",
      hash_including(target: "toast-container", locals: hash_including(type: :alert))
    )

    described_class.perform_now(take.id, user.id)

    take.reload
    expect(take.status).to eq("failed")
    expect(take.stock_take_items.first.adjusted).to eq(false)
    expect(kitchen.ingredient_stock(ingredient).quantity_on_hand.to_d).to eq(0)
  end
end
