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

  it "converts quantities to the purchase unit with ceiling on requested qty" do
    ingredient = make_ingredient(name: "Oil", on_hand: 1500, max: 10_000)
    ingredient.ingredient_units.create!(
      unit: "gallons",
      base_units_per_unit: 3785,
      purchase_unit: true,
      company: company
    )

    lines = described_class.new(supplier: supplier).call
    line = lines.sole

    expect(line.display_unit).to eq("gallons")
    expect(line.balance).to be_within(0.001).of(1500 / 3785.0)
    expect(line.max_quantity).to be_within(0.001).of(10_000 / 3785.0)
    expect(line.requested_quantity).to eq(((10_000 - 1500) / 3785.0).ceil)
    expect(line.requested_whole_units).to be(true)
    expect(line.estimated_cents).to eq(500 * line.requested_quantity)
  end

  it "falls back to the base unit when no purchase unit is set" do
    make_ingredient(name: "Chicken", on_hand: 4, max: 10)

    line = described_class.new(supplier: supplier).call.sole

    expect(line.display_unit).to eq("kg")
    expect(line.requested_quantity).to eq(6)
    expect(line.requested_whole_units).to be(false)
  end
end
