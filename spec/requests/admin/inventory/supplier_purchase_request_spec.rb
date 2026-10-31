# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Suppliers purchase request", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company, name: "Kitchen A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(
      :ingredient,
      company: company,
      ingredient_category: category,
      name: "Chicken",
      quantity_on_hand: 4,
      max_quantity: 10,
      reorder_threshold: 1
    )
  end
  let(:supplier) { Supplier.create!(name: "Meat Co", company: company, lead_time_days: 2, active: true) }

  before do
    Current.company = company
    sign_in owner
    SupplierIngredient.create!(
      supplier: supplier,
      ingredient: ingredient,
      price_cents: 1_000,
      preferred: true,
      vendor_product_name: "Whole Chicken",
      vendor_sku: "CHK-1"
    )
    IngredientLocation.create!(
      ingredient: ingredient,
      location: location,
      quantity_on_hand: 2,
      reorder_threshold: 1,
      max_quantity: 8
    )
    ingredient.update_column(:quantity_on_hand, 4)
  end

  it "shows a generate purchase request link on the vendor page's ingredients tab" do
    get_supplier_tab(supplier, "ingredients")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.suppliers.show.purchase_request"))
    expect(response.body).to include(purchase_request_admin_inventory_supplier_path(supplier))
  end

  it "renders a printable purchase request with company-level suggested qty" do
    get purchase_request_admin_inventory_supplier_path(supplier)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Chicken")
    expect(response.body).to include("Whole Chicken")
    expect(response.body).to include("6")
  end

  it "uses location max and balance when filtered" do
    get purchase_request_admin_inventory_supplier_path(supplier, location_id: location.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(location.name)
    expect(response.body).to include("6") # 8 - 2
  end

  it "exports CSV rows for suggested lines" do
    get purchase_request_admin_inventory_supplier_path(supplier, format: :csv)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Chicken")
    expect(response.body).to include("CHK-1")
    expect(response.body).to include("6.0")
  end

  it "shows empty state when nothing needs ordering" do
    ingredient.update_columns(max_quantity: 0)
    IngredientLocation.where(ingredient: ingredient).update_all(max_quantity: 0)

    get purchase_request_admin_inventory_supplier_path(supplier)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.suppliers.purchase_request.empty_title"))
  end

  def number_with_precision(number, precision:)
    ActionController::Base.helpers.number_with_precision(number, precision: precision)
  end
end
