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

  describe "manually-added source stock" do
    it "becomes transferable after a manual add at the source (a batch is created)" do
      fresh = create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 0)
      transfer = create(:stock_transfer, company: company, from_location: kitchen, to_location: branch, requested_by: owner)
      line = create(:stock_transfer_line, stock_transfer: transfer, ingredient: fresh, quantity_requested: 5)

      # No batch at the source yet → nothing transferable.
      expect(line.transferable_quantity_at_source).to eq(0)

      StockAdjustment.create!(ingredient: fresh, user: owner, location: kitchen,
        quantity_delta: 8, adjustment_type: "manual_add", maintain_batches: true)

      expect(line.transferable_quantity_at_source).to eq(8)
    end
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

    it "saves counted on-hand and order limit with the requested quantity" do
      post admin_inventory_stock_transfers_path, params: {
        stock_transfer: {
          from_location_id: kitchen.id,
          to_location_id: branch.id,
          stock_transfer_lines_attributes: {
            "0" => {
              ingredient_id: ingredient.id,
              unit: ingredient.unit,
              order_limit: 20,
              counted_quantity: 6,
              quantity_requested_input: 14
            }
          }
        }
      }

      line = StockTransfer.last.stock_transfer_lines.first
      expect(line.order_limit).to eq(20)
      expect(line.counted_quantity).to eq(6)
      expect(line.quantity_requested).to eq(14)
    end

    it "records a backdated transfer date on create" do
      transfer_date = Date.current - 2

      post admin_inventory_stock_transfers_path, params: {
        stock_transfer: {
          from_location_id: kitchen.id,
          to_location_id: branch.id,
          transferred_on: transfer_date,
          stock_transfer_lines_attributes: {
            "0" => { ingredient_id: ingredient.id, quantity_requested: 3.0 }
          }
        }
      }

      transfer = StockTransfer.last
      expect(transfer.transferred_on).to eq(transfer_date)
      expect(transfer.requested_at.to_date).to eq(transfer_date)
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
      IngredientLocation.find_by(location: kitchen, ingredient: ingredient).update!(quantity_on_hand: 1.0)
      StockBatch.where(ingredient: ingredient, location: kitchen).update_all(quantity_remaining: 1.0)

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "4" }
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

    it "allows sending more than source stock when restrict mode is off" do
      Setting.set("restrict_stock_transfers_to_source", false)
      transfer = create_transfer_with_line(requested: 10.0)
      line = transfer.stock_transfer_lines.first
      IngredientLocation.find_by(location: kitchen, ingredient: ingredient).update!(quantity_on_hand: 2.0)
      StockBatch.where(ingredient: ingredient, location: kitchen).update_all(quantity_remaining: 2.0)

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "10" }
      }

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(flash[:alert]).to be_blank
      expect(transfer.reload).to be_awaiting_receipt
      expect(line.reload.quantity_sent.to_d).to eq(10)

      post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: {
        lines: { line.id => "10" }
      }

      expect(transfer.reload).to be_completed
      kitchen_il = IngredientLocation.find_by(location: kitchen, ingredient: ingredient)
      branch_il = IngredientLocation.find_by(location: branch, ingredient: ingredient)
      expect(kitchen_il.quantity_on_hand.to_d).to eq(-8)
      expect(branch_il.quantity_on_hand.to_d).to eq(10)
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
      # Global on-hand = sum of locations (7.5 + 2.5); a transfer just moves it.
      expect(ingredient.reload.quantity_on_hand.to_d).to eq(10.0)
    end

    it "stamps send, receive, batches, and adjustments on the transfer date" do
      transfer_date = Date.current - 2
      transfer = create_transfer_with_line(requested: 4.0)
      transfer.update!(transferred_on: transfer_date)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "4.0" } }
      expect(transfer.reload.sent_at.to_date).to eq(transfer_date)
      expect(transfer.stock_transfer_shipments.last.sent_at.to_date).to eq(transfer_date)

      post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "4.0" } }

      expect(transfer.reload.received_at.to_date).to eq(transfer_date)
      expect(transfer.stock_transfer_shipments.last.received_at.to_date).to eq(transfer_date)

      adjustments = StockAdjustment.where(stock_transfer: transfer)
      expect(adjustments).to be_present
      expect(adjustments.map { |a| a.created_at.to_date }.uniq).to eq([transfer_date])

      batch = StockBatch.find_by(location: branch, ingredient: ingredient)
      expect(batch.received_on).to eq(transfer_date)
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

  describe "POST void_shipment" do
    it "voids an in-transit shipment and returns the transfer to requested without moving stock" do
      transfer = create_transfer_with_line(requested: 4.0)
      line = transfer.stock_transfer_lines.first
      kitchen_before = IngredientLocation.find_by(location: kitchen, ingredient: ingredient).quantity_on_hand.to_d

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "3.5" } }
      expect(transfer.reload).to be_awaiting_receipt

      post void_shipment_admin_inventory_stock_transfer_path(transfer)

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(flash[:notice]).to eq(I18n.t("flash.stock_transfer.shipment_voided"))
      expect(transfer.reload).to be_requested
      expect(line.reload.quantity_sent.to_d).to eq(0)
      expect(transfer.stock_transfer_shipments.last).to be_voided
      expect(StockAdjustment.where(stock_transfer: transfer)).to be_empty
      expect(IngredientLocation.find_by(location: kitchen, ingredient: ingredient).quantity_on_hand.to_d).to eq(kitchen_before)
    end

    it "voids a later in-transit shipment and returns the transfer to partially received" do
      transfer = create_transfer_with_line(requested: 10.0)
      line = transfer.stock_transfer_lines.first

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "6" } }
      post confirm_receipt_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "6" } }
      expect(transfer.reload).to be_partially_received

      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: { lines: { line.id => "4" } }
      expect(transfer.reload).to be_awaiting_receipt

      post void_shipment_admin_inventory_stock_transfer_path(transfer)

      expect(transfer.reload).to be_partially_received
      expect(line.reload.quantity_sent.to_d).to eq(6.0)
      expect(line.quantity_received.to_d).to eq(6.0)
      expect(transfer.stock_transfer_shipments.in_transit).to be_empty
      expect(transfer.stock_transfer_shipments.last).to be_voided
    end

    it "rejects void when no shipment is in transit" do
      transfer = create_transfer_with_line

      post void_shipment_admin_inventory_stock_transfer_path(transfer)

      expect(response).to redirect_to(admin_inventory_stock_transfer_path(transfer))
      expect(flash[:alert]).to eq(I18n.t("inventory.stock_transfers.errors.cannot_void_shipment"))
      expect(transfer.reload).to be_requested
    end
  end
end
