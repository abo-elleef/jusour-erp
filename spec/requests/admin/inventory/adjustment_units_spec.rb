# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock adjustments in an alternate unit", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:oil) do
    ing = create(:ingredient, company: company, ingredient_category: category, name: "Oil", unit: "ml", quantity_on_hand: 0.0)
    ing.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, company: company)
    ing
  end

  before do
    Current.company = company
    sign_in owner
  end

  it "stores the delta in base but records the entered unit, and shows both" do
    post adjust_admin_inventory_ingredient_path(oil), params: {
      location_id: kitchen.id,
      quantity_delta: "2", unit: "gallons",
      adjustment_type: StockAdjustment::ADJUSTMENT_TYPES.first, reason_notes: "restock"
    }

    adj = oil.stock_adjustments.order(:created_at).last
    expect(adj.quantity_delta.to_d).to eq(7570) # 2 gallons → 7570 ml stored in base
    expect(adj.unit).to eq("gallons")
    expect(oil.reload.quantity_on_hand.to_d).to eq(7570)

    get admin_inventory_ingredient_path(oil)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("gallon") # shown in the entered unit, not just base
    expect(response.body).to include('data-ingredient-units')
    expect(response.body).to include(I18n.t("inventory.ingredients.show.units.base"))
    expect(response.body).to include(I18n.t("inventory.ingredients.show.units.alternate"))
    expect(response.body).to include("3785")
  end

  it "requires a location and records no adjustment without one" do
    expect {
      post adjust_admin_inventory_ingredient_path(oil), params: {
        quantity_delta: "1", unit: "ml", adjustment_type: "manual_add"
      }
    }.not_to change(StockAdjustment, :count)

    expect(flash[:alert]).to be_present
  end

  it "creates a location batch so a manual add is costed and transferable" do
    post adjust_admin_inventory_ingredient_path(oil), params: {
      location_id: kitchen.id, quantity_delta: "500", unit: "ml", adjustment_type: "manual_add"
    }

    batches = oil.stock_batches.where(location: kitchen)
    expect(batches.sum(:quantity_remaining)).to eq(500)
    expect(kitchen.ingredient_stock(oil).quantity_on_hand.to_d).to eq(500)
  end
end
