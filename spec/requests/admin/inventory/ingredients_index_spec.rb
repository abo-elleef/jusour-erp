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

RSpec.describe "Admin::Inventory::Ingredients index supplier filter", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:linked) { create(:ingredient, company: company, ingredient_category: category, name: "Linked Flour") }
  let!(:unlinked) { create(:ingredient, company: company, ingredient_category: category, name: "Unlinked Oil") }
  let!(:other_linked) { create(:ingredient, company: company, ingredient_category: category, name: "Other Spice") }
  let(:supplier) { Supplier.create!(name: "Grain Co", company: company, active: true) }
  let(:other_supplier) { Supplier.create!(name: "Spice Co", company: company, active: true) }
  let!(:inactive_supplier) { Supplier.create!(name: "Closed Co", company: company, active: false) }

  before do
    Current.company = company
    sign_in owner
    SupplierIngredient.create!(supplier: supplier, ingredient: linked, price_cents: 100)
    SupplierIngredient.create!(supplier: other_supplier, ingredient: other_linked, price_cents: 100)
  end

  it "filters to ingredients linked to the selected supplier" do
    get admin_inventory_ingredients_path(supplier_id: supplier.id)
    expect(response.body).to include("Linked Flour")
    expect(response.body).not_to include("Unlinked Oil")
    expect(response.body).not_to include("Other Spice")
  end

  it "filters to ingredients with no supplier linked" do
    get admin_inventory_ingredients_path(supplier_id: "none")
    expect(response.body).to include("Unlinked Oil")
    expect(response.body).not_to include("Linked Flour")
    expect(response.body).not_to include("Other Spice")
  end

  it "lists only active suppliers in the filter dropdown" do
    get admin_inventory_ingredients_path
    expect(response.body).to include("Grain Co")
    expect(response.body).to include("Spice Co")
    expect(response.body).not_to include("Closed Co")
    expect(response.body).to include(I18n.t("inventory.ingredients.index.no_supplier"))
  end

  it "ignores an unknown supplier_id" do
    get admin_inventory_ingredients_path(supplier_id: SecureRandom.uuid)
    expect(response.body).to include("Linked Flour")
    expect(response.body).to include("Unlinked Oil")
    expect(response.body).to include("Other Spice")
  end
end
