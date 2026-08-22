# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Supplier count sheet", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:other_supplier) { Supplier.create!(name: "Other Co", company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:produce) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:dairy) { IngredientCategory.create!(name: "Dairy", position: 2, company: company) }

  def ingredient(name, category: produce, active: true)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 0,
      active: active, company: company)
  end

  def stock_at(ing, location, qty = 5, sup: supplier, vendor_product: nil, sku: nil)
    SupplierIngredient.find_or_create_by!(supplier: sup, ingredient: ing) do |si|
      si.vendor_product_name = vendor_product
      si.vendor_sku = sku
    end
    location.ingredient_locations.create!(ingredient: ing, quantity_on_hand: qty, reorder_threshold: 1)
    ing
  end

  before { sign_in owner }

  # Header cell text only — page chrome reuses some of the same words.
  def table_headers(body)
    body.scan(/<thead.*?<\/thead>/m).join.scan(/<th[^>]*>(.*?)<\/th>/m).flatten.map(&:strip)
  end

  it "asks for a location before building anything" do
    stock_at(ingredient("Tomatoes"), kitchen)

    get count_sheet_admin_inventory_supplier_path(supplier)

    expect(response.body).to include(I18n.t("inventory.count_sheet.pick_location"))
    expect(response.body).not_to include("Tomatoes")
  end

  it "lists this vendor's stocked ingredients at the chosen location" do
    stock_at(ingredient("Tomatoes"), kitchen, 7, vendor_product: "Vine Tomato 5kg", sku: "VT-5")

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    expect(response.body).to include("Tomatoes")
    # The vendor's own naming is what the counter recognises on the shelf.
    expect(response.body).to include("Vine Tomato 5kg", "VT-5")
    expect(response.body).to include(I18n.t("inventory.count_sheet.actual_count"))
  end

  it "is blind by default — no system balance column on the sheet" do
    stock_at(ingredient("Tomatoes"), kitchen, 7)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    # Scope to the header: the toggle's own label contains the same word.
    expect(table_headers(response.body))
      .not_to include(I18n.t("inventory.count_sheet.system_balance"))
    expect(table_headers(response.body))
      .to include(I18n.t("inventory.count_sheet.actual_count"))
    expect(response.body).to include(I18n.t("inventory.count_sheet.show_balance"))
  end

  it "shows the balance only when explicitly asked" do
    # number_with_precision strips trailing zeros, so 7 renders as "7" — a string
    # that appears all over the page. Use a fractional value that can only come
    # from the balance cell.
    stock_at(ingredient("Tomatoes"), kitchen, 7.25)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id, show_balance: 1)

    expect(table_headers(response.body))
      .to include(I18n.t("inventory.count_sheet.system_balance"))
    expect(response.body).to include("7.25")
  end

  it "groups rows by category" do
    stock_at(ingredient("Tomatoes", category: produce), kitchen)
    stock_at(ingredient("Milk", category: dairy), kitchen)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    # Produce has the lower position, so it heads the sheet.
    expect(response.body.index("Produce")).to be < response.body.index("Dairy")
  end

  it "excludes another vendor's ingredients" do
    stock_at(ingredient("Tomatoes"), kitchen)
    stock_at(ingredient("Not Ours"), kitchen, 3, sup: other_supplier)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    expect(response.body).to include("Tomatoes")
    expect(response.body).not_to include("Not Ours")
  end

  it "excludes stock held at a different location" do
    stock_at(ingredient("Tomatoes"), kitchen)
    stock_at(ingredient("Branch Only"), branch)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    expect(response.body).to include("Tomatoes")
    expect(response.body).not_to include("Branch Only")
  end

  it "excludes archived ingredients, matching what a stock take would seed" do
    stock_at(ingredient("Tomatoes"), kitchen)
    stock_at(ingredient("Retired", active: false), kitchen)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    expect(response.body).not_to include("Retired")
  end

  it "says so when the vendor has nothing stocked there" do
    stock_at(ingredient("Tomatoes"), kitchen)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: branch.id)

    expect(response.body).to include(
      I18n.t("inventory.suppliers.count_sheet.empty", location: branch.name)
    )
  end

  # Without print-flow the global `section:not(...)` rule wins on specificity,
  # break-inside:avoid applies, and a long table jumps to the next page leaving
  # the first one mostly blank.
  it "lets the table break across pages" do
    stock_at(ingredient("Tomatoes"), kitchen)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    expect(response.body).to match(/<section class="print-flow/)
    expect(response.body).not_to include("print:break-inside-auto")
  end

  it "creates no stock take — printing commits nothing" do
    stock_at(ingredient("Tomatoes"), kitchen)

    expect { get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id) }
      .not_to change(StockTake, :count)
  end

  it "is reachable from the vendor page" do
    get admin_inventory_supplier_path(supplier)

    expect(response.body).to include(count_sheet_admin_inventory_supplier_path(supplier))
    expect(response.body).to include(I18n.t("inventory.suppliers.count_sheet.action"))
  end

  it "carries a signature and date line for the paper" do
    stock_at(ingredient("Tomatoes"), kitchen)

    get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

    expect(response.body).to include(I18n.t("inventory.count_sheet.counted_by"))
    expect(response.body).to include(I18n.t("inventory.count_sheet.count_date"))
  end
end
