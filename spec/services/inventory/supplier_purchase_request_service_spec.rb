# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::SupplierPurchaseRequestService do
  let(:company) { Current.company }
  let(:category) { create(:ingredient_category, company: company) }
  let(:location) { create(:location, company: company, name: "Kitchen") }
  let(:supplier) { Supplier.create!(name: "Meat Co", company: company, lead_time_days: 2) }

  def make_ingredient(name:, on_hand:, max:, location_on_hand: nil, location_max: nil)
    ingredient = create(
      :ingredient,
      company: company,
      ingredient_category: category,
      name: name,
      quantity_on_hand: on_hand,
      max_quantity: max,
      reorder_threshold: 1
    )
    IngredientLocation.create!(
      ingredient: ingredient,
      location: location,
      quantity_on_hand: location_on_hand.nil? ? on_hand : location_on_hand,
      reorder_threshold: 1,
      max_quantity: location_max.nil? ? max : location_max
    )
    ingredient.update_column(:quantity_on_hand, on_hand)
    SupplierIngredient.create!(supplier: supplier, ingredient: ingredient, price_cents: 500, preferred: true)
    ingredient
  end

  it "returns company-level max − balance lines and skips zero max / non-positive qty" do
    need = make_ingredient(name: "Chicken", on_hand: 4, max: 10)
    make_ingredient(name: "Oil", on_hand: 2, max: 0)
    make_ingredient(name: "Salt", on_hand: 8, max: 5)

    lines = described_class.new(supplier: supplier).call

    expect(lines.map { |l| l.ingredient.name }).to eq(["Chicken"])
    line = lines.first
    expect(line.ingredient).to eq(need)
    expect(line.balance).to eq(4)
    expect(line.max_quantity).to eq(10)
    expect(line.requested_quantity).to eq(6)
    expect(line.estimated_cents).to eq(3_000)
  end

  it "uses location balance and max when a location is provided" do
    make_ingredient(name: "Chicken", on_hand: 15, max: 20, location_on_hand: 3, location_max: 12)

    lines = described_class.new(supplier: supplier, location: location).call

    expect(lines.size).to eq(1)
    expect(lines.first.balance).to eq(3)
    expect(lines.first.max_quantity).to eq(12)
    expect(lines.first.requested_quantity).to eq(9)
  end

  it "skips lines already at location max" do
    make_ingredient(name: "Chicken", on_hand: 15, max: 20, location_on_hand: 12, location_max: 12)

    expect(described_class.new(supplier: supplier, location: location).call).to eq([])
  end
end
