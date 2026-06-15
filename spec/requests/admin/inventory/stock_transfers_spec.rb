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

  def create_transfer_with_line
    transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient, quantity_requested: 4.0)
    transfer
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
      transfer = create_transfer_with_line
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
    it "marks transfer as sent with quantities" do
      transfer = create_transfer_with_line
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "3.5" }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(transfer.reload).to be_sent
      expect(line.reload.quantity_sent.to_d).to eq(3.5)
    end

    it "rejects when source stock is insufficient" do
      transfer = create_transfer_with_line
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "50" }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(flash[:alert]).to be_present
      expect(transfer.reload).to be_requested
    end
  end

  describe "POST confirm_receipt" do
    it "moves stock between locations on receipt confirmation" do
      transfer = create_transfer_with_line
      line = transfer.stock_transfer_lines.first
      line.update!(quantity_sent: 3.0)
      transfer.update!(status: "sent", sent_at: Time.current, sent_by: owner)

      expect {
        post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: {
          lines: { line.id => "2.5" }
        }
      }.to change(StockAdjustment, :count).by(2)

      expect(transfer.reload).to be_received
      expect(line.reload.quantity_received.to_d).to eq(2.5)

      kitchen_il = IngredientLocation.find_by(location: kitchen, ingredient: ingredient)
      branch_il = IngredientLocation.find_by(location: branch, ingredient: ingredient)
      expect(kitchen_il.quantity_on_hand.to_d).to eq(7.5)
      expect(branch_il.quantity_on_hand.to_d).to eq(2.5)
      expect(ingredient.reload.quantity_on_hand.to_d).to eq(20.0)
    end
  end
end
