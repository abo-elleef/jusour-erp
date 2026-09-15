# frozen_string_literal: true

require "rails_helper"

# Creating an ingredient and linking its vendor used to be two separate steps
# (create, then assign a supplier on the edit page). The new-ingredient form now
# carries an optional supplier section that is saved in the same request.
RSpec.describe "Creating an ingredient with its supplier in one step", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:unit_id) do
    Ingredient.create!(name: "Seed", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, company: company).unit_id
  end
  let!(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }

  before { sign_in owner }

  def create_ingredient(ingredient_attrs: {}, supplier_attrs: nil)
    params = {
      ingredient: {
        name: "Tomatoes", ingredient_category_id: category.id, unit_id: unit_id,
        reorder_threshold: 1, cost_per_unit_dollars: "7.50"
      }.merge(ingredient_attrs)
    }
    params[:supplier_ingredient] = supplier_attrs if supplier_attrs
    post admin_inventory_ingredients_path, params: params
    Ingredient.find_by(name: params[:ingredient][:name])
  end

  it "links the chosen supplier while creating the ingredient" do
    ingredient = create_ingredient(supplier_attrs: {
      supplier_id: supplier.id, price_dollars: "9.25", preferred: "1",
      vendor_product_name: "Roma tomato 5kg", vendor_sku: "FF-118"
    })

    link = ingredient.supplier_ingredients.sole
    expect(link.supplier).to eq(supplier)
    expect(link.price_cents).to eq(925)
    expect(link).to be_preferred
    expect(link.vendor_product_name).to eq("Roma tomato 5kg")
    expect(link.vendor_sku).to eq("FF-118")
  end

  it "falls back to the cost per unit typed on the same form when no price is given" do
    ingredient = create_ingredient(supplier_attrs: { supplier_id: supplier.id, price_dollars: "" })

    expect(ingredient.supplier_ingredients.sole.price_cents).to eq(750)
  end

  it "creates the ingredient with no link when no supplier is chosen" do
    ingredient = create_ingredient(supplier_attrs: { supplier_id: "", price_dollars: "9.25" })

    expect(ingredient).to be_present
    expect(ingredient.supplier_ingredients).to be_empty
  end

  it "still works when the form carries no supplier section at all" do
    expect(create_ingredient.supplier_ingredients).to be_empty
  end

  it "honours an unchecked preferred box" do
    ingredient = create_ingredient(supplier_attrs: { supplier_id: supplier.id, preferred: "0" })

    expect(ingredient.supplier_ingredients.sole).not_to be_preferred
  end

  it "ignores an inactive supplier rather than linking it" do
    supplier.update!(active: false)

    ingredient = create_ingredient(supplier_attrs: { supplier_id: supplier.id })

    expect(ingredient).to be_present
    expect(ingredient.supplier_ingredients).to be_empty
  end

  it "saves neither the ingredient nor the link when the ingredient is invalid" do
    ingredients_before = Ingredient.count + 1 # the "Seed" ingredient backing `unit_id`

    create_ingredient(ingredient_attrs: { name: "" },
      supplier_attrs: { supplier_id: supplier.id, price_dollars: "9.25" })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Ingredient.count).to eq(ingredients_before)
    expect(SupplierIngredient.count).to eq(0)
  end

  it "renders the supplier picker on the new-ingredient form" do
    get new_admin_inventory_ingredient_path

    expect(response.body).to include("supplier_ingredient[supplier_id]")
    expect(response.body).to include("Fresh Farms")
  end
end
