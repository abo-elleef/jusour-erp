# frozen_string_literal: true

require "rails_helper"

# Mirrors the user/location scoping: an ingredient is usable everywhere by
# default, and can be scoped down to specific locations from its edit page.
RSpec.describe "Scoping an ingredient to specific locations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:branch_a) { Location.create!(name: "Branch A", location_type: "branch", company: company) }
  let!(:branch_b) { Location.create!(name: "Branch B", location_type: "branch", company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, company: company)
  end

  before { sign_in owner }

  it "renders the location checkboxes on the edit page" do
    get edit_admin_inventory_ingredient_path(ingredient)

    expect(response.body).to include("ingredient[all_locations]")
    expect(response.body).to include("ingredient[restricted_location_ids][]")
    expect(response.body).to include(branch_a.name)
    expect(response.body).to include(branch_b.name)
  end

  it "defaults to all_locations" do
    expect(ingredient.all_locations).to be true
    expect(ingredient.accessible_location_ids).to match_array([branch_a.id, branch_b.id])
  end

  it "scopes the ingredient down to the chosen locations" do
    patch admin_inventory_ingredient_path(ingredient), params: {
      ingredient: { all_locations: "0", restricted_location_ids: [branch_a.id] }
    }
    ingredient.reload

    expect(response).to redirect_to(admin_inventory_ingredient_path(ingredient))
    expect(ingredient.all_locations).to be false
    expect(ingredient.restricted_location_ids).to eq([branch_a.id])
    expect(ingredient.can_access_location?(branch_a)).to be true
    expect(ingredient.can_access_location?(branch_b)).to be false
  end

  it "reverting to all_locations ignores any leftover selections" do
    ingredient.update!(all_locations: false, restricted_location_ids: [branch_a.id])

    patch admin_inventory_ingredient_path(ingredient), params: {
      ingredient: { all_locations: "1", restricted_location_ids: [""] }
    }
    ingredient.reload

    expect(ingredient.all_locations).to be true
    expect(ingredient.accessible_location_ids).to match_array([branch_a.id, branch_b.id])
  end
end
