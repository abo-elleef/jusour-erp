# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Company units", type: :model do
  let(:company) { create(:company) }
  let(:category) { IngredientCategory.create!(name: "Oils", position: 1, company: company) }

  before { Current.company = company }

  it "seeds the built-in units when a company is created" do
    expect(company.units.where(system: true).pluck(:name)).to match_array(Unit::DEFAULTS)
    expect(company.units.count).to eq(Unit::DEFAULTS.size)
  end

  it "lets an ingredient use a custom company unit" do
    company.units.create!(name: "tin", active: true)
    ing = Ingredient.new(name: "Ghee", ingredient_category: category, unit: "tin",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)
    expect(ing).to be_valid
  end

  it "rejects a unit not configured for the company" do
    ing = Ingredient.new(name: "Ghee", ingredient_category: category, unit: "furlong",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)
    expect(ing).not_to be_valid
    expect(ing.errors[:unit]).to be_present
  end

  it "rejects an alternate ingredient unit not configured for the company" do
    ing = Ingredient.create!(name: "Ghee", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)
    iu = ing.ingredient_units.build(unit: "furlong", base_units_per_unit: 5, company: company)
    expect(iu).not_to be_valid
  end

  it "enforces unique names per company (case-insensitive)" do
    dup = company.units.build(name: "KG", active: true)
    expect(dup).not_to be_valid
  end

  it "treats built-in and custom units identically: both deletable when unused" do
    expect(company.units.find_by(name: "kg").deletable?).to be(true)
    expect(company.units.create!(name: "carton").deletable?).to be(true)
  end

  it "is not deletable while an ingredient uses it (base or alternate)" do
    tin = company.units.create!(name: "tin")
    Ingredient.create!(name: "Ghee", ingredient_category: category, unit: "tin",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)
    expect(tin.reload.in_use?).to be(true)
    expect(tin.deletable?).to be(false)
  end

  it "renames an in-use custom unit without orphaning references (FK by id)" do
    tin = company.units.create!(name: "tin")
    ing = Ingredient.create!(name: "Ghee", ingredient_category: category, unit: "tin",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)

    tin.update!(name: "canister")

    expect(ing.reload.unit_id).to eq(tin.id)
    expect(ing.unit).to eq("canister")
  end

  it "renames a built-in (system) unit too — references follow by id" do
    kg = company.units.find_by(name: "kg")
    ing = Ingredient.create!(name: "Flour", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: company)

    kg.update!(name: "kilogram")

    expect(kg.reload.system).to be(true)
    expect(ing.reload.unit_id).to eq(kg.id)
    expect(ing.unit).to eq("kilogram")
  end
end
