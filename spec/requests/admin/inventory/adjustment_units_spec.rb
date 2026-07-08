# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock adjustments in an alternate unit", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
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
  end
end
