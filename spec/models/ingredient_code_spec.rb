# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ingredient, "reference code", type: :model do
  let(:category) { IngredientCategory.create!(name: "Proteins", position: 1, active: true) }

  def ingredient(attrs = {})
    create(:ingredient, { ingredient_category: category }.merge(attrs))
  end

  it "auto-assigns a <CATEGORY_CODE>-NNN code, sequential within the category" do
    a = ingredient
    b = ingredient
    expect(a.code).to eq("PROTEINS-001")
    expect(b.code).to eq("PROTEINS-002")
  end

  it "numbers sequences independently per category" do
    other = IngredientCategory.create!(name: "Dairy", position: 2, active: true)
    here = ingredient
    there = create(:ingredient, ingredient_category: other)
    expect(here.code).to eq("PROTEINS-001")
    expect(there.code).to eq("DAIRY-001")
  end

  it "keeps a custom code and skips it in the auto sequence" do
    custom = ingredient(code: "PROT-X")
    expect(custom.code).to eq("PROT-X")
    expect(ingredient.code).to eq("PROTEINS-001")
  end

  it "rejects a duplicate code within the company (case-insensitive)" do
    ingredient(code: "DUP-1")
    dup = build(:ingredient, ingredient_category: category, code: "dup-1")
    expect(dup).not_to be_valid
    expect(dup.errors[:code]).to be_present
  end

  it "reassigns an auto-generated code when the ingredient moves to another category" do
    other = IngredientCategory.create!(name: "Dairy", position: 2, active: true)
    create(:ingredient, ingredient_category: other, code: "DAIRY-001")
    ing = ingredient

    ing.update!(ingredient_category: other)

    expect(ing.code).to eq("DAIRY-002")
  end

  it "keeps a custom code when the ingredient moves to another category" do
    other = IngredientCategory.create!(name: "Dairy", position: 2, active: true)
    custom = ingredient(code: "SPECIAL-9")

    custom.update!(ingredient_category: other)

    expect(custom.code).to eq("SPECIAL-9")
  end
end
