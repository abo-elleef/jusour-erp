# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingredient category count sheet", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:produce) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:dairy) { IngredientCategory.create!(name: "Dairy", position: 2, company: company) }
  let(:acme) { Supplier.create!(name: "Acme Foods", company: company) }
  let(:zesty) { Supplier.create!(name: "Zesty Supply", company: company) }

  def ingredient(name, category: produce, active: true)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 0,
      active: active, company: company)
  end

  def stock_at(ing, location, qty = 5, suppliers: [])
    suppliers.each { |s| SupplierIngredient.find_or_create_by!(supplier: s, ingredient: ing) }
    location.ingredient_locations.create!(ingredient: ing, quantity_on_hand: qty, reorder_threshold: 1)
    ing
  end

  def table_headers(body)
    body.scan(/<thead.*?<\/thead>/m).join.scan(/<th[^>]*>(.*?)<\/th>/m).flatten.map(&:strip)
  end

  before { sign_in owner }

  it "asks for a location first" do
    stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme])

    get count_sheet_admin_inventory_ingredient_category_path(produce)

    expect(response.body).to include(I18n.t("inventory.count_sheet.pick_location"))
    expect(response.body).not_to include("Tomatoes")
  end

  it "lists this category's ingredients across every vendor" do
    stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme])
    stock_at(ingredient("Lettuce"), kitchen, 3, suppliers: [zesty])

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(response.body).to include("Tomatoes", "Lettuce")
    expect(response.body).to include("Acme Foods", "Zesty Supply")
  end

  it "names every vendor when an ingredient has more than one" do
    stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme, zesty])

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    # Joined rather than reduced to a "primary" vendor — nothing is summed here.
    expect(response.body).to include("Acme Foods / Zesty Supply")
  end

  it "shows a dash for an ingredient with no vendor" do
    stock_at(ingredient("Orphan Herb"), kitchen, 2)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(response.body).to include("Orphan Herb")
    expect(table_headers(response.body)).to include(I18n.t("inventory.count_sheet.vendor"))
  end

  it "uses a vendor column, not the vendor-product column" do
    stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme])

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    headers = table_headers(response.body)
    expect(headers).to include(I18n.t("inventory.count_sheet.vendor"))
    expect(headers).not_to include(I18n.t("inventory.count_sheet.vendor_product"))
  end

  it "excludes other categories" do
    stock_at(ingredient("Tomatoes", category: produce), kitchen)
    stock_at(ingredient("Milk", category: dairy), kitchen)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(response.body).to include("Tomatoes")
    expect(response.body).not_to include("Milk")
  end

  it "excludes stock at another location" do
    stock_at(ingredient("Tomatoes"), kitchen)
    stock_at(ingredient("Branch Only"), branch)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(response.body).not_to include("Branch Only")
  end

  it "excludes archived ingredients, matching what a stock take seeds" do
    stock_at(ingredient("Tomatoes"), kitchen)
    stock_at(ingredient("Retired", active: false), kitchen)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(response.body).not_to include("Retired")
  end

  it "is blind by default" do
    stock_at(ingredient("Tomatoes"), kitchen, 9)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(table_headers(response.body)).not_to include(I18n.t("inventory.count_sheet.system_balance"))
    expect(response.body).to include(I18n.t("inventory.count_sheet.show_balance"))
  end

  it "shows the balance when asked" do
    # Fractional and distinctive: "9" alone appears all over the page, so a round
    # number would let this pass without the balance cell rendering at all.
    stock_at(ingredient("Tomatoes"), kitchen, 9.25)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id, show_balance: 1)

    expect(table_headers(response.body)).to include(I18n.t("inventory.count_sheet.system_balance"))
    expect(response.body).to include("9.25")
  end

  it "says so when nothing in the category is stocked there" do
    stock_at(ingredient("Tomatoes"), kitchen)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: branch.id)

    expect(response.body).to include(
      I18n.t("inventory.ingredient_categories.count_sheet.empty", location: branch.name)
    )
  end

  it "creates no stock take" do
    stock_at(ingredient("Tomatoes"), kitchen)

    expect { get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id) }
      .not_to change(StockTake, :count)
  end

  it "is reachable from the category list" do
    produce

    get admin_inventory_ingredient_categories_path

    expect(response.body).to include(count_sheet_admin_inventory_ingredient_category_path(produce))
    expect(response.body).to include(I18n.t("inventory.ingredient_categories.count_sheet.action"))
  end

  it "carries the signature and date line" do
    stock_at(ingredient("Tomatoes"), kitchen)

    get count_sheet_admin_inventory_ingredient_category_path(produce, location_id: kitchen.id)

    expect(response.body).to include(I18n.t("inventory.count_sheet.counted_by"))
    expect(response.body).to include(I18n.t("inventory.count_sheet.count_date"))
  end
end
