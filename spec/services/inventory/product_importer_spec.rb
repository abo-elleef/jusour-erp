# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ProductImporter do
  let(:company) { create(:company) }
  before { Current.company = company }

  def row(code:, name:, unit_raw: "قطعة", cost: "", selling_price: "")
    { "code" => code, "name" => name, "unit_raw" => unit_raw, "cost" => cost, "selling_price" => selling_price }
  end

  def import(rows, dry_run: false)
    described_class.new(rows: rows, company: company, dry_run: dry_run).call
  end

  it "imports products with code, unit, cost and selling price" do
    result = import([row(code: "13", name: "Articulating Paper 80", cost: "93.13", selling_price: "120")])

    expect(result.created).to eq(1)
    p = Ingredient.where(company: company).find_by(code: "13")
    expect(p.name).to eq("Articulating Paper 80")
    expect(p.unit).to eq("pieces")                 # قطعة mapped
    expect(p.cost_per_unit_cents).to eq(9_313)     # 93.13
    expect(p.selling_price_cents).to eq(12_000)    # 120.00
    expect(p.ingredient_category.name).to eq("Imported products")
  end

  it "is idempotent by code (re-run updates, not duplicates)" do
    import([row(code: "13", name: "Old name", selling_price: "100")])
    result = import([row(code: "13", name: "New name", selling_price: "150")])

    expect(result.updated).to eq(1)
    expect(Ingredient.where(company: company).where(code: "13").count).to eq(1)
    p = Ingredient.where(company: company).find_by(code: "13")
    expect(p.name).to eq("New name")
    expect(p.selling_price_cents).to eq(15_000)
  end

  it "skips rows with no name" do
    result = import([row(code: "99", name: "")])
    expect(result.skipped_no_name).to eq(1)
    expect(Ingredient.where(company: company).count).to eq(0)
  end

  it "dry_run persists nothing" do
    result = import([row(code: "13", name: "Ghost")], dry_run: true)
    expect(result.created).to eq(1)
    expect(Ingredient.where(company: company).count).to eq(0)
  end
end
