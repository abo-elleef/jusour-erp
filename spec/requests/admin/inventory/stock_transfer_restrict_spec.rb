# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stock transfer restrict-to-source setting", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Oil", quantity_on_hand: 10.0) }

  before do
    Current.company = company
    sign_in owner
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 10.0)
    StockBatch.create!(
      ingredient: ingredient,
      location: kitchen,
      quantity_received: 10.0,
      quantity_remaining: 10.0,
      cost_per_unit_cents: 500,
      received_on: Date.current
    )
  end

  def set_source_stock(qty)
    IngredientLocation.find_by!(location: kitchen, ingredient: ingredient).update!(quantity_on_hand: qty)
    StockBatch.where(ingredient: ingredient, location: kitchen).update_all(quantity_remaining: qty)
  end

  def request_transfer(qty)
    post admin_inventory_stock_transfers_path, params: {
      stock_transfer: {
        from_location_id: kitchen.id,
        to_location_id: branch.id,
        stock_transfer_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity_requested: qty }
        }
      }
    }
    StockTransfer.last
  end

  def send_and_receive(transfer, qty)
    line = transfer.stock_transfer_lines.first
    post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => qty.to_s } }
    post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => qty.to_s } }
    [transfer.reload, line.reload]
  end

  shared_examples "request / send / receive when source covers the quantity" do
    it "lets the team request, send, and receive a covered quantity" do
      transfer = request_transfer(4.0)
      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(transfer).to be_requested

      transfer, line = send_and_receive(transfer, 4.0)
      expect(flash[:alert]).to be_blank
      expect(transfer).to be_completed
      expect(line.quantity_sent.to_d).to eq(4)
      expect(line.quantity_received.to_d).to eq(4)

      kitchen_il = IngredientLocation.find_by(location: kitchen, ingredient: ingredient)
      branch_il = IngredientLocation.find_by(location: branch, ingredient: ingredient)
      expect(kitchen_il.quantity_on_hand.to_d).to eq(6)
      expect(branch_il.quantity_on_hand.to_d).to eq(4)

      get admin_inventory_stock_transfer_path(transfer)
      expect(response.body).not_to include("data-source-shortage-report")
    end
  end

  context "when restrict mode is on (default)" do
    it_behaves_like "request / send / receive when source covers the quantity"

    it "still allows requesting more than source has" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)

      expect(transfer).to be_requested
      expect(transfer.stock_transfer_lines.first.quantity_requested.to_d).to eq(8)
    end

    it "rejects send above source stock" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "8" } }

      expect(flash[:alert]).to be_present
      expect(transfer.reload).to be_requested
      expect(line.reload.quantity_sent.to_d).to eq(0)
    end

    it "sends only what is available, then receive moves that amount" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "2" } }
      expect(transfer.reload).to be_awaiting_receipt

      post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "2" } }
      expect(transfer.reload).to be_partially_received
      expect(line.reload.quantity_received.to_d).to eq(2)
      expect(IngredientLocation.find_by(location: kitchen, ingredient: ingredient).quantity_on_hand.to_d).to eq(0)
      expect(IngredientLocation.find_by(location: branch, ingredient: ingredient).quantity_on_hand.to_d).to eq(2)
    end

    it "highlights lines that are short at source on the show page" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)

      get admin_inventory_stock_transfer_path(transfer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-short-at-source="true"')
      expect(response.body).to include(I18n.t("inventory.stock_transfers.short_at_source"))
      expect(response.body).not_to include("data-source-shortage-report")
    end

    it "lists source shortage on a completed transfer even when restrict mode is on" do
      transfer = request_transfer(4.0)
      send_and_receive(transfer, 4.0)
      set_source_stock(-3.0)

      get admin_inventory_stock_transfer_path(transfer.reload)

      expect(transfer).to be_completed
      expect(response.body).to include("data-source-shortage-report")
      expect(response.body).to include(I18n.t("inventory.stock_transfers.source_shortage_heading"))
      expect(response.body).to include("Oil")
    end
  end

  context "when restrict mode is off" do
    before { Setting.set("restrict_stock_transfers_to_source", false) }

    it_behaves_like "request / send / receive when source covers the quantity"

    it "allows requesting more than source has" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)

      expect(transfer).to be_requested
      expect(transfer.stock_transfer_lines.first.quantity_requested.to_d).to eq(8)
    end

    it "sends and receives above source stock and lets source go negative" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)
      transfer, line = send_and_receive(transfer, 8.0)

      expect(flash[:alert]).to be_blank
      expect(transfer).to be_completed
      expect(line.quantity_sent.to_d).to eq(8)
      expect(line.quantity_received.to_d).to eq(8)
      expect(IngredientLocation.find_by(location: kitchen, ingredient: ingredient).quantity_on_hand.to_d).to eq(-6)
      expect(IngredientLocation.find_by(location: branch, ingredient: ingredient).quantity_on_hand.to_d).to eq(8)

      get admin_inventory_stock_transfer_path(transfer)
      expect(response.body).to include('data-source-shortage-report')
      expect(response.body).to include(I18n.t("inventory.stock_transfers.source_shortage_heading"))
      expect(response.body).to include("Oil")
    end

    it "still highlights lines that are short at source on the show page" do
      set_source_stock(2.0)
      transfer = request_transfer(8.0)

      get admin_inventory_stock_transfer_path(transfer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-short-at-source="true"')
      expect(response.body).to include(I18n.t("inventory.stock_transfers.short_at_source"))
      expect(response.body).to include(I18n.t("inventory.stock_transfers.send_unrestricted_hint"))
    end
  end
end
