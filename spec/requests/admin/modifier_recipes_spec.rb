# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin modifier recipes", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:category) { IngredientCategory.create!(name: "Meat", position: 1, company: company) }
  let!(:ball) do
    ing = Ingredient.create!(name: "Beef ball", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 2000, quantity_on_hand: 0, company: company)
    ing.ingredient_units.create!(unit: "pieces", base_units_per_unit: 0.05, company: company)
    ing
  end
  let(:group) { ModifierGroup.create!(company: company, name: "Size") }
  let(:double) { group.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500) }

  before { sign_in owner }

  it "offers the ingredient's units on the edit page" do
    get edit_admin_modifier_group_modifier_path(group, double)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="modifier_recipe[unit]"', "recipe-unit")
  end

  it "saves the chosen unit and shows the converted cost" do
    post admin_modifier_group_modifier_modifier_recipes_path(group, double),
      params: { modifier_recipe: { ingredient_id: ball.id, quantity: "1", unit: "pieces" } }

    mr = double.modifier_recipes.sole
    expect(mr.unit).to eq("pieces")
    expect(mr.base_quantity).to eq(BigDecimal("0.05"))

    follow_redirect!
    expect(response.body).to include("1.00") # 0.05 batch × 20.00 = 1.00 per Double
  end
end
