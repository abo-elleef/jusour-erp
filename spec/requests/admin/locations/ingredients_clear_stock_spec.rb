# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Locations::Ingredients clear stock", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 0)
  end

  before do
    Current.company = company
    sign_in owner
    IngredientLocation.create!(
      ingredient: ingredient,
      location: location,
      quantity_on_hand: 7,
      reorder_threshold: 1
    )
    ingredient.update_column(:quantity_on_hand, 7)
  end

  it "clears all positive balances at the location" do
    expect do
      post clear_stock_admin_location_ingredients_path(location)
    end.to change { StockAdjustment.where(location: location).count }.by(1)

    expect(response).to redirect_to(admin_location_ingredients_path(location))
    expect(ingredient.ingredient_locations.find_by!(location: location).quantity_on_hand).to eq(0)
    expect(ingredient.reload.quantity_on_hand).to eq(0)
    expect(StockAdjustment.last.adjustment_type).to eq("clear_all_stock")
  end

  it "shows the clear button when stock is present" do
    get admin_location_ingredients_path(location)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.locations.clear_stock"))
  end

  it "renders a balance history chart for selected ingredients" do
    get admin_location_ingredients_path(location, chart_ingredient_ids: [ingredient.id], chart_days: 30)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.locations.balance_history.title"))
    expect(response.body).to include("Chartkick")
    expect(response.body).to include(ingredient.name)
  end
end
