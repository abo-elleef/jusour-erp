# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingredient cost-per-unit param handling", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 750, quantity_on_hand: 10, company: company)
  end

  before { sign_in owner }

  def update_with(attrs)
    patch admin_inventory_ingredient_path(ingredient), params: { ingredient: attrs }
    ingredient.reload
  end

  it "leaves the cost alone when the field is absent from the request" do
    # The regression: an absent key used to coerce to 0 and wipe a maintained cost.
    update_with(name: "Tomatoes (vine)")

    expect(ingredient.name).to eq("Tomatoes (vine)")
    expect(ingredient.cost_per_unit_cents).to eq(750)
  end

  it "updates the cost when the field is supplied" do
    update_with(cost_per_unit_dollars: "12.50")

    expect(ingredient.cost_per_unit_cents).to eq(1_250)
  end

  it "treats a present-but-blank field as clearing the cost to zero" do
    update_with(cost_per_unit_dollars: "")

    expect(ingredient.cost_per_unit_cents).to eq(0)
  end

  it "accepts an explicit zero" do
    update_with(cost_per_unit_dollars: "0")

    expect(ingredient.cost_per_unit_cents).to eq(0)
  end

  it "rounds sub-cent input rather than truncating" do
    update_with(cost_per_unit_dollars: "1.005")

    expect(ingredient.cost_per_unit_cents).to eq(101)
  end

  it "defaults a new ingredient with no cost field to zero" do
    post admin_inventory_ingredients_path, params: {
      ingredient: { name: "Basil", ingredient_category_id: category.id,
                    unit_id: ingredient.unit_id, reorder_threshold: 1 }
    }

    expect(Ingredient.find_by(name: "Basil").cost_per_unit_cents).to eq(0)
  end

  it "does not disturb other attributes while preserving the cost" do
    update_with(reorder_threshold: 9)

    expect(ingredient.reorder_threshold).to eq(9)
    expect(ingredient.cost_per_unit_cents).to eq(750)
  end
end
