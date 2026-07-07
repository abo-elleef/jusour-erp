# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock transfers in a fixed unit", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:oil) do
    ing = create(:ingredient, company: company, ingredient_category: category, name: "Oil", unit: "ml", quantity_on_hand: 0.0)
    ing.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, company: company)
    ing
  end

  before do
    Current.company = company
    sign_in owner
    create(:ingredient_location, location: kitchen, ingredient: oil, quantity_on_hand: 7570.0)
    StockBatch.create!(ingredient: oil, location: kitchen, quantity_received: 7570.0,
      quantity_remaining: 7570.0, cost_per_unit_cents: 1, received_on: Date.current)
  end

  it "requests, ships and receives in gallons while moving base-unit (ml) stock" do
    post admin_inventory_stock_transfers_path, params: {
      stock_transfer: {
        from_location_id: kitchen.id, to_location_id: branch.id,
        stock_transfer_lines_attributes: {
          "0" => { ingredient_id: oil.id, quantity_requested_input: "2", unit: "gallons" }
        }
      }
    }

    transfer = StockTransfer.last
    line = transfer.stock_transfer_lines.first
    # 2 gallons stored as 7570 ml in the base unit, unit locked to gallons.
    expect(line.quantity_requested.to_d).to eq(7570)
    expect(line.unit).to eq("gallons")

    # Ship 2 gallons → 7570 ml
    post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "2" } }
    expect(line.reload.quantity_sent.to_d).to eq(7570)

    # Receive 2 gallons → 7570 ml moved kitchen → branch
    post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "2" } }
    expect(line.reload.quantity_received.to_d).to eq(7570)

    branch_il = IngredientLocation.find_by(location: branch, ingredient: oil)
    expect(branch_il.quantity_on_hand.to_d).to eq(7570)
    expect(IngredientLocation.find_by(location: kitchen, ingredient: oil).quantity_on_hand.to_d).to eq(0)
  end
end
