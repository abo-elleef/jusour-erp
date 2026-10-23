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

RSpec.describe "Admin::Inventory::Ingredients index missing stock settings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "prompts when reorder at and max are unset" do
    create(:ingredient, company: company, ingredient_category: category, name: "Unset Oil",
      reorder_threshold: 0, max_quantity: 0)

    get admin_inventory_ingredients_path
    expect(response.body).to include(I18n.t("inventory.ingredients.index.reorder_missing"))
    expect(response.body).to include(I18n.t("inventory.ingredients.index.max_missing"))
  end

  it "does not prompt when reorder at and max are set" do
    create(:ingredient, company: company, ingredient_category: category, name: "Set Flour",
      reorder_threshold: 3, max_quantity: 20)

    get admin_inventory_ingredients_path
    expect(response.body).not_to include(I18n.t("inventory.ingredients.index.reorder_missing"))
    expect(response.body).not_to include(I18n.t("inventory.ingredients.index.max_missing"))
    expect(response.body).to include(I18n.t("inventory.ingredients.index.reorder_at", threshold: 3))
    expect(response.body).to include(I18n.t("inventory.ingredients.index.max_at", quantity: 20))
  end
end

RSpec.describe "Admin::Inventory::Ingredients index location filter", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  # users.wages_account_code is NOT NULL with nothing in the app that sets it.
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 9101) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:branch_a) { Location.create!(name: "Branch A", location_type: "branch", company: company) }
  let(:branch_b) { Location.create!(name: "Branch B", location_type: "branch", company: company) }
  let(:everywhere) do
    create(:ingredient, company: company, ingredient_category: category, name: "Everywhere Tomatoes")
  end
  let(:only_a) do
    create(:ingredient, company: company, ingredient_category: category, name: "Branch Salt",
      all_locations: false, restricted_location_ids: [branch_a.id])
  end

  before do
    Current.company = company
    sign_in owner
  end

  it "keeps company-wide ingredients and those scoped to the chosen location" do
    everywhere
    only_a
    get admin_inventory_ingredients_path(location_id: branch_a.id)

    expect(response.body).to include("Everywhere Tomatoes")
    expect(response.body).to include("Branch Salt")
    expect(response.body).to include("Branch A")
  end

  it "hides an ingredient scoped to a different location" do
    everywhere
    only_a
    get admin_inventory_ingredients_path(location_id: branch_b.id)

    expect(response.body).to include("Everywhere Tomatoes")
    expect(response.body).not_to include("Branch Salt")
  end

  it "ignores an unknown location and lists every ingredient" do
    everywhere
    only_a
    get admin_inventory_ingredients_path(location_id: SecureRandom.uuid)

    expect(response.body).to include("Everywhere Tomatoes")
    expect(response.body).to include("Branch Salt")
  end

  it "keeps the location when another filter link is followed" do
    everywhere
    get admin_inventory_ingredients_path(location_id: branch_a.id)

    link = Nokogiri::HTML(response.body).at_css("a[href*='status=inactive']")
    expect(link["href"]).to include("location_id=#{branch_a.id}")
  end
end
