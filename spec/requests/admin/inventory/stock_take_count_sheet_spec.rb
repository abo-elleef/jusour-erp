# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock take count sheet", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:produce) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:dairy) { IngredientCategory.create!(name: "Dairy", position: 2, company: company) }
  let(:acme) { Supplier.create!(name: "Acme Foods", company: company) }
  let(:zesty) { Supplier.create!(name: "Zesty Supply", company: company) }

  def ingredient(name, category: produce)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 0,
      active: true, company: company)
  end

  def stock_at(ing, location, qty = 5, suppliers: [])
    suppliers.each { |s| SupplierIngredient.find_or_create_by!(supplier: s, ingredient: ing) }
    location.ingredient_locations.create!(ingredient: ing, quantity_on_hand: qty, reorder_threshold: 1)
    ing
  end

  def start_take(location: kitchen, supplier: nil)
    post admin_inventory_stock_takes_path,
      params: { location_id: location.id, supplier_id: supplier&.id }
    StockTake.order(:created_at).last
  end

  # "System" and bare numbers also occur in the page chrome, so balance assertions
  # look only inside the sheet's own tables.
  def sheet_tables(body)
    body.scan(/<table[^>]*border-collapse.*?<\/table>/m).join
  end

  def group_labels(body)
    body.scan(/<h2[^>]*>\s*(.*?)\s*<span/m).flatten.map(&:strip)
  end

  before { sign_in owner }

  it "lists exactly the items in the take, grouped by category" do
    stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme])
    stock_at(ingredient("Milk", category: dairy), kitchen, 3, suppliers: [zesty])
    stock_at(ingredient("Elsewhere"), branch, 7, suppliers: [acme])
    take = start_take

    get count_sheet_admin_inventory_stock_take_path(take)

    expect(response.body).to include("Tomatoes", "Milk")
    expect(response.body).not_to include("Elsewhere")
    expect(group_labels(response.body)).to eq(%w[Produce Dairy])
  end

  it "does not offer a location picker — the take fixes the location" do
    stock_at(ingredient("Tomatoes"), kitchen, 5)
    take = start_take

    get count_sheet_admin_inventory_stock_take_path(take)

    expect(response.body).to include("Central Kitchen")
    expect(response.body).not_to include(I18n.t("inventory.count_sheet.build"))
    expect(response.body).not_to include(I18n.t("inventory.count_sheet.select_location"))
  end

  it "is blind by default and shows the balance only when asked" do
    stock_at(ingredient("Tomatoes"), kitchen, 42)
    take = start_take

    get count_sheet_admin_inventory_stock_take_path(take)
    expect(sheet_tables(response.body)).not_to include(I18n.t("inventory.count_sheet.system_balance"))
    expect(sheet_tables(response.body)).not_to include("42")

    get count_sheet_admin_inventory_stock_take_path(take, show_balance: 1)
    expect(sheet_tables(response.body)).to include(I18n.t("inventory.count_sheet.system_balance"))
    expect(sheet_tables(response.body)).to include("42")
  end

  it "prints the expected quantity the take recorded, not a fresh reading" do
    tomatoes = stock_at(ingredient("Tomatoes"), kitchen, 42)
    take = start_take
    # Stock moves after the count started; the paper must still match the take.
    kitchen.ingredient_locations.find_by(ingredient: tomatoes).update!(quantity_on_hand: 99)

    get count_sheet_admin_inventory_stock_take_path(take, show_balance: 1)

    expect(sheet_tables(response.body)).to include("42")
    expect(sheet_tables(response.body)).not_to include("99")
  end

  it "names the supplier when the take spans vendors" do
    stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme, zesty])
    take = start_take

    get count_sheet_admin_inventory_stock_take_path(take)

    expect(response.body).to include(I18n.t("inventory.count_sheet.vendor"))
    expect(response.body).to include("Acme Foods / Zesty Supply")
  end

  it "prints the vendor's own product name when the take is scoped to one vendor" do
    tomatoes = stock_at(ingredient("Tomatoes"), kitchen, 5, suppliers: [acme])
    SupplierIngredient.find_by(supplier: acme, ingredient: tomatoes)
      .update!(vendor_product_name: "Roma Tomato Case", vendor_sku: "RT-12")
    stock_at(ingredient("Lettuce"), kitchen, 3, suppliers: [zesty])
    take = start_take(supplier: acme)

    get count_sheet_admin_inventory_stock_take_path(take)

    expect(response.body).to include(I18n.t("inventory.count_sheet.vendor_product"))
    expect(response.body).to include("Roma Tomato Case", "RT-12")
    expect(response.body).not_to include("Lettuce")
  end

  it "keeps an ingredient deactivated mid-count on the paper" do
    tomatoes = stock_at(ingredient("Tomatoes"), kitchen, 5)
    take = start_take
    tomatoes.update!(active: false)

    get count_sheet_admin_inventory_stock_take_path(take)

    expect(response.body).to include("Tomatoes")
  end

  it "links to the sheet from the stock take page" do
    stock_at(ingredient("Tomatoes"), kitchen, 5)
    take = start_take

    get admin_inventory_stock_take_path(take)

    expect(response.body).to include(count_sheet_admin_inventory_stock_take_path(take))
    expect(response.body).to include(I18n.t("inventory.stock_takes.show.print_count_sheet"))
  end
end
