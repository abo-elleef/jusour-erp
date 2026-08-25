# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Closing a stock transfer short", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 500)
  end
  let(:transfer) do
    create(:stock_transfer, company: company, from_location: kitchen,
      to_location: branch, requested_by: owner)
  end
  let!(:line) do
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient,
      quantity_requested: 24, position: 0)
  end

  before do
    Current.company = company
    sign_in owner
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 500)
    StockBatch.create!(ingredient: ingredient, location: kitchen, quantity_received: 500,
      quantity_remaining: 500, cost_per_unit_cents: 100, received_on: Date.current)
  end

  def dispatch_and_receive(sent:, received:, notes: nil)
    ::Inventory::SendStockTransferService.new(
      transfer, owner, line_quantities: { line.id.to_s => sent.to_s }
    ).call
    post confirm_receipt_admin_inventory_stock_transfer_path(transfer),
      params: { lines: { line.id.to_s => received.to_s }, receipt_notes: notes }.compact
    transfer.reload
  end

  describe "the gap it closes" do
    it "is offered once a transfer is partially received" do
      dispatch_and_receive(sent: 24, received: 18)

      expect(transfer.status).to eq("partially_received")
      expect(transfer.can_close_short?).to be(true)
    end

    it "finishes the transfer and clears it from the open queue" do
      dispatch_and_receive(sent: 24, received: 18)

      post close_short_admin_inventory_stock_transfer_path(transfer),
        params: { closed_short_reason: "damaged in transit" }

      transfer.reload
      expect(transfer.status).to eq("completed")
      expect(StockTransfer.in_progress).not_to include(transfer)
    end

    it "records who accepted the shortfall and why" do
      dispatch_and_receive(sent: 24, received: 18)

      post close_short_admin_inventory_stock_transfer_path(transfer),
        params: { closed_short_reason: "damaged in transit" }

      transfer.reload
      expect(transfer).to be_closed_short
      expect(transfer.closed_short_by).to eq(owner)
      expect(transfer.closed_short_reason).to eq("damaged in transit")
    end

    it "stays distinguishable from a transfer where everything arrived" do
      dispatch_and_receive(sent: 24, received: 24)

      expect(transfer.status).to eq("completed")
      expect(transfer).not_to be_closed_short
    end

    it "moves no stock — the shortfall is written off, not returned" do
      dispatch_and_receive(sent: 24, received: 18)

      expect {
        post close_short_admin_inventory_stock_transfer_path(transfer),
          params: { closed_short_reason: "damaged" }
      }.not_to change(StockAdjustment, :count)
    end

    it "insists on a reason" do
      dispatch_and_receive(sent: 24, received: 18)

      post close_short_admin_inventory_stock_transfer_path(transfer),
        params: { closed_short_reason: "  " }

      expect(transfer.reload.status).to eq("partially_received")
      expect(flash[:alert]).to eq(I18n.t("inventory.stock_transfers.errors.close_short_reason_required"))
    end

    it "refuses on a transfer that has shipped nothing — cancel that instead" do
      post close_short_admin_inventory_stock_transfer_path(transfer),
        params: { closed_short_reason: "nope" }

      expect(transfer.reload.status).to eq("requested")
      expect(flash[:alert]).to eq(I18n.t("inventory.stock_transfers.errors.cannot_close_short"))
    end

    it "refuses while a shipment is still in transit" do
      ::Inventory::SendStockTransferService.new(
        transfer, owner, line_quantities: { line.id.to_s => "24" }
      ).call

      post close_short_admin_inventory_stock_transfer_path(transfer),
        params: { closed_short_reason: "nope" }

      expect(transfer.reload.status).to eq("awaiting_receipt")
      expect(flash[:alert]).to eq(I18n.t("inventory.stock_transfers.errors.cannot_close_short"))
    end
  end

  describe "the shortfall record" do
    it "keeps the note entered at receipt" do
      dispatch_and_receive(sent: 24, received: 18, notes: "two boxes missing on arrival")

      shipment = transfer.stock_transfer_shipments.last
      expect(shipment.receipt_notes).to eq("two boxes missing on arrival")
    end

    it "flags the shipment as short and names the gap" do
      dispatch_and_receive(sent: 24, received: 18)
      shipment = transfer.stock_transfer_shipments.last

      expect(shipment).to be_short
      expect(shipment.short_lines.size).to eq(1)
      short = shipment.short_lines.first
      expect(short.quantity_sent.to_d - short.quantity_received.to_d).to eq(6)
    end

    it "does not flag a shipment that arrived in full" do
      dispatch_and_receive(sent: 24, received: 24)

      expect(transfer.stock_transfer_shipments.last).not_to be_short
    end

    it "surfaces the note and the shortfall on the transfer page" do
      dispatch_and_receive(sent: 24, received: 18, notes: "two boxes missing")

      get admin_inventory_stock_transfer_path(transfer)

      expect(response.body).to include("two boxes missing")
      expect(response.body).to include(I18n.t("inventory.stock_transfers.shipment_shortfall"))
    end

    it "shows the closed-short reason on the page afterwards" do
      dispatch_and_receive(sent: 24, received: 18)
      post close_short_admin_inventory_stock_transfer_path(transfer),
        params: { closed_short_reason: "damaged in transit" }

      get admin_inventory_stock_transfer_path(transfer)

      expect(response.body).to include(I18n.t("inventory.stock_transfers.closed_short_badge"))
      expect(response.body).to include("damaged in transit")
    end
  end
end
