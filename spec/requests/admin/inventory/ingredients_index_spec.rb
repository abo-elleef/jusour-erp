# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Ingredients index status filter", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:active_ing) { create(:ingredient, company: company, ingredient_category: category, name: "Active Salt", active: true) }
  let!(:inactive_ing) { create(:ingredient, company: company, ingredient_category: category, name: "Retired Sugar", active: false) }

  before do
    Current.company = company
    sign_in owner
  end

  it "shows only active ingredients by default" do
    get admin_inventory_ingredients_path
    expect(response.body).to include("Active Salt")
    expect(response.body).not_to include("Retired Sugar")
  end

  it "shows only inactive ingredients with status=inactive" do
    get admin_inventory_ingredients_path(status: "inactive")
    expect(response.body).to include("Retired Sugar")
    expect(response.body).not_to include("Active Salt")
  end

  it "shows both with status=all" do
    get admin_inventory_ingredients_path(status: "all")
    expect(response.body).to include("Active Salt")
    expect(response.body).to include("Retired Sugar")
  end

  it "falls back to active for an unknown status value" do
    get admin_inventory_ingredients_path(status: "bogus")
    expect(response.body).to include("Active Salt")
    expect(response.body).not_to include("Retired Sugar")
  end
end
