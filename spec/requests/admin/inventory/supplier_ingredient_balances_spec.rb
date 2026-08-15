# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Suppliers show ingredient balances", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location_a) { create(:location, company: company, name: "Kitchen A") }
  let(:location_b) { create(:location, company: company, name: "Branch B") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, name: "Chicken", quantity_on_hand: 0)
  end
  let(:supplier) { Supplier.create!(name: "Meat Co", company: company, lead_time_days: 2) }

  before do
    Current.company = company
    sign_in owner
    SupplierIngredient.create!(
      supplier: supplier,
      ingredient: ingredient,
      price_cents: 1_000,
      preferred: true
    )
    IngredientLocation.create!(ingredient: ingredient, location: location_a, quantity_on_hand: 12, reorder_threshold: 2)
    IngredientLocation.create!(ingredient: ingredient, location: location_b, quantity_on_hand: 3, reorder_threshold: 2)
    ingredient.update_column(:quantity_on_hand, 15)
  end

  it "shows company-wide balance by default" do
    ingredient.update_columns(max_quantity: 20)
    get admin_inventory_supplier_path(supplier)
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/15\s*<span class="text-xs font-normal text-gray-500"/)
    expect(response.body).to include(I18n.t("inventory.suppliers.show.all_locations"))
    expect(response.body).to include(I18n.t("inventory.suppliers.show.max_quantity"))
    expect(response.body).to match(/>\s*20\s*</)
  end

  it "filters balance to the selected location" do
    IngredientLocation.where(ingredient: ingredient, location: location_a).update_all(max_quantity: 18)
    get admin_inventory_supplier_path(supplier, location_id: location_a.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.suppliers.show.ingredients_hint_location", location: location_a.name))
    expect(response.body).to match(/12\s*<span class="text-xs font-normal text-gray-500"/)
    expect(response.body).not_to match(/15\s*<span class="text-xs font-normal text-gray-500"/)
    expect(response.body).to match(/>\s*18\s*</)
  end

  it "renders a sticky ingredients table header" do
    get admin_inventory_supplier_path(supplier)
    expect(response.body).to include("sticky top-0")
    expect(response.body).to include("max-h-[60vh]")
  end

  it "sorts ingredients by name and preserves the location filter" do
    beef = create(:ingredient, company: company, ingredient_category: category, name: "Beef", quantity_on_hand: 1)
    SupplierIngredient.create!(supplier: supplier, ingredient: beef, price_cents: 500)
    IngredientLocation.create!(ingredient: beef, location: location_a, quantity_on_hand: 1, reorder_threshold: 1)

    get admin_inventory_supplier_path(supplier, location_id: location_a.id, sort: "ingredient", dir: "asc")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("sort=ingredient")
    expect(response.body).to include("location_id=#{location_a.id}")
    expect(order_of(%w[Beef Chicken])).to eq(%w[Beef Chicken])

    get admin_inventory_supplier_path(supplier, location_id: location_a.id, sort: "ingredient", dir: "desc")
    expect(order_of(%w[Beef Chicken])).to eq(%w[Chicken Beef])
  end

  def order_of(names)
    body = response.body
    names.sort_by { |n| body.index(">#{n}<") || body.index(n) || Float::INFINITY }
  end
end
