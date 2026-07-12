# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::StockTransfers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 20.0) }

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

  def create_transfer_with_line(requested: 10.0)
    transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient, quantity_requested: requested)
    transfer
  end

  describe "GET /admin/inventory/stock_transfers/:id" do
    it "renders the transfer with a print button and print-only letterhead" do
      transfer = create_transfer_with_line

      get admin_inventory_stock_transfer_path(transfer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("window.print()")
      expect(response.body).to include(I18n.t("inventory.stock_transfers.print_document_title"))
    end
  end

  describe "POST /admin/inventory/stock_transfers" do
    it "creates a transfer request" do
      expect {
        post admin_inventory_stock_transfers_path, params: {
          stock_transfer: {
            from_location_id: kitchen.id,
            to_location_id: branch.id,
            notes: "Weekly restock",
            stock_transfer_lines_attributes: {
              "0" => { ingredient_id: ingredient.id, quantity_requested: 3.0 }
            }
          }
        }
      }.to change(StockTransfer, :count).by(1)
        .and change(StockTransferLine, :count).by(1)

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(StockTransfer.last))
      expect(StockTransfer.last).to be_requested
    end
  end

  describe "PATCH /admin/inventory/stock_transfers/:id" do
    it "updates lines and removes a nested line" do
      transfer = create_transfer_with_line(requested: 4.0)
      item2 = create(:ingredient, company: company, ingredient_category: category)
      line = transfer.stock_transfer_lines.first

      patch admin_inventory_stock_transfer_path(transfer), params: {
        stock_transfer: {
          from_location_id: kitchen.id,
          to_location_id: branch.id,
          notes: "Updated",
          stock_transfer_lines_attributes: {
            "0" => { id: line.id, ingredient_id: ingredient.id, quantity_requested: 2.0, _destroy: "1" },
            "1" => { ingredient_id: item2.id, quantity_requested: 1.5 }
          }
        }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(transfer.reload.stock_transfer_lines.count).to eq(1)
      expect(transfer.stock_transfer_lines.first.ingredient).to eq(item2)
    end
  end

  describe "POST send_transfer" do
    it "marks transfer as awaiting receipt with quantities" do
      transfer = create_transfer_with_line(requested: 4.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "3.5" }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(transfer.reload).to be_awaiting_receipt
      expect(line.reload.quantity_sent.to_d).to eq(3.5)
      expect(transfer.stock_transfer_shipments.count).to eq(1)
    end

    it "rejects when source stock is insufficient" do
      transfer = create_transfer_with_line(requested: 4.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "50" }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(flash[:alert]).to be_present
      expect(transfer.reload).to be_requested
    end
    it "rejects send when batch stock is lower than ingredient location on-hand" do
      transfer = create_transfer_with_line(requested: 10.0)
      line = transfer.stock_transfer_lines.first
      IngredientLocation.find_by(location: kitchen, ingredient: ingredient).update!(quantity_on_hand: 10.0)
      StockBatch.where(ingredient: ingredient, location: kitchen).update_all(quantity_remaining: 2.0)

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "10" }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(flash[:alert]).to be_present
      expect(transfer.reload).to be_requested
    end
  end

  describe "POST confirm_receipt" do
    it "moves stock between locations on receipt confirmation" do
      transfer = create_transfer_with_line(requested: 4.0)
      line = transfer.stock_transfer_lines.first
      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "3.0" } }

      expect {
        post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: {
          lines: { line.id => "2.5" }
        }
      }.to change(StockAdjustment, :count).by(2)

      expect(transfer.reload).to be_partially_received
      expect(line.reload.quantity_received.to_d).to eq(2.5)

      kitchen_il = IngredientLocation.find_by(location: kitchen, ingredient: ingredient)
      branch_il = IngredientLocation.find_by(location: branch, ingredient: ingredient)
      expect(kitchen_il.quantity_on_hand.to_d).to eq(7.5)
      expect(branch_il.quantity_on_hand.to_d).to eq(2.5)
      expect(ingredient.reload.quantity_on_hand.to_d).to eq(20.0)
    end

    it "supports partial send, confirm, then send and confirm the remainder" do
      transfer = create_transfer_with_line(requested: 10.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "6" } }
      expect(transfer.reload).to be_awaiting_receipt

      post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "6" } }
      expect(transfer.reload).to be_partially_received
      expect(line.reload.quantity_received.to_d).to eq(6.0)
      expect(line.quantity_pending_send.to_d).to eq(4.0)

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "4" } }
      expect(transfer.reload).to be_awaiting_receipt

      post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "4" } }
      expect(transfer.reload).to be_completed
      expect(line.reload.quantity_received.to_d).to eq(10.0)
      expect(transfer.stock_transfer_shipments.count).to eq(2)

      kitchen_il = IngredientLocation.find_by(location: kitchen, ingredient: ingredient)
      branch_il = IngredientLocation.find_by(location: branch, ingredient: ingredient)
      expect(kitchen_il.quantity_on_hand.to_d).to eq(0.0)
      expect(branch_il.quantity_on_hand.to_d).to eq(10.0)
    end

    it "blocks sending while a shipment awaits receipt" do
      transfer = create_transfer_with_line(requested: 10.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "6" } }
      expect(transfer.reload).to be_awaiting_receipt

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "4" } }
      expect(flash[:alert]).to be_present
      expect(transfer.reload).to be_awaiting_receipt
    end
  end
end
