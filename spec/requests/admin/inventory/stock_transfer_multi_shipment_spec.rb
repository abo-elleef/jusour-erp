# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Multiple open shipments and receiver-as-truth", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:branch) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 900)
  end
  let(:transfer) do
    create(:stock_transfer, company: company, from_location: kitchen,
      to_location: branch, requested_by: owner)
  end
  let!(:line) do
    create(:stock_transfer_line, stock_transfer: transfer, ingredient: ingredient,
      quantity_requested: 30, position: 0)
  end

  before do
    Current.company = company
    sign_in owner
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 900)
    StockBatch.create!(ingredient: ingredient, location: kitchen, quantity_received: 900,
      quantity_remaining: 900, cost_per_unit_cents: 100, received_on: Date.current)
  end

  def send_qty(qty)
    ::Inventory::SendStockTransferService.new(
      transfer, owner, line_quantities: { line.id.to_s => qty.to_s }
    ).call
    transfer.reload
  end

  def confirm(shipment, qty)
    post confirm_receipt_admin_inventory_stock_transfer_path(transfer),
      params: { shipment_id: shipment.id, lines: { line.id.to_s => qty.to_s } }
    transfer.reload
  end

  describe "a second batch can leave before the first is confirmed" do
    it "opens two shipments at once" do
      send_qty(10)
      send_qty(12)

      expect(transfer.open_shipments.count).to eq(2)
      expect(transfer.status).to eq("awaiting_receipt")
      expect(line.reload.quantity_open_in_transit).to eq(22)
      expect(line.quantity_pending_send).to eq(8)
    end

    it "receives the earlier shipment, not just the latest" do
      send_qty(10)
      first = transfer.open_shipments.first
      send_qty(12)

      confirm(first, 10)

      expect(first.reload.status).to eq("received")
      expect(transfer.open_shipments.count).to eq(1)
      # Still awaiting the second, so the transfer must not settle yet.
      expect(transfer.status).to eq("awaiting_receipt")
      expect(line.reload.quantity_received).to eq(10)
    end

    it "settles only once every shipment is closed" do
      send_qty(10)
      first = transfer.open_shipments.first
      send_qty(20)
      second = transfer.open_shipments.last

      confirm(first, 10)
      expect(transfer.status).to eq("awaiting_receipt")

      confirm(second, 20)
      expect(transfer.reload.status).to eq("completed")
    end

    it "voids a named shipment and leaves the other open" do
      send_qty(10)
      first = transfer.open_shipments.first
      send_qty(12)

      post void_shipment_admin_inventory_stock_transfer_path(transfer),
        params: { shipment_id: first.id }

      expect(first.reload.status).to eq("voided")
      expect(transfer.reload.open_shipments.count).to eq(1)
      expect(transfer.status).to eq("awaiting_receipt")
      # The voided shipment's quantities go back to pending.
      expect(line.reload.quantity_pending_send).to eq(18)
    end

    it "renders a receive form for every open shipment" do
      send_qty(10)
      send_qty(12)

      get admin_inventory_stock_transfer_path(transfer)

      expect(response.body.scan(/name="shipment_id"/).size).to eq(2)
    end

    it "rejects a shipment id from another transfer" do
      send_qty(10)
      other = create(:stock_transfer, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)
      other_line = create(:stock_transfer_line, stock_transfer: other, ingredient: ingredient,
        quantity_requested: 5, position: 0)
      ::Inventory::SendStockTransferService.new(
        other, owner, line_quantities: { other_line.id.to_s => "5" }
      ).call
      foreign = other.reload.open_shipments.first

      post confirm_receipt_admin_inventory_stock_transfer_path(transfer),
        params: { shipment_id: foreign.id, lines: { line.id.to_s => "10" } }

      expect(foreign.reload.status).to eq("in_transit")
      expect(line.reload.quantity_received).to eq(0)
    end
  end

  describe "the receiver is the source of truth" do
    it "accepts more than was recorded as sent" do
      send_qty(10)
      shipment = transfer.open_shipments.first

      confirm(shipment, 12)

      expect(line.reload.quantity_received).to eq(12)
      expect(shipment.reload).to be_surplus
    end

    it "moves the surplus stock too" do
      send_qty(10)
      shipment = transfer.open_shipments.first

      expect { confirm(shipment, 12) }
        .to change { branch.ingredient_locations.find_by(ingredient: ingredient)&.quantity_on_hand.to_d }.by(12)
    end

    it "counts the surplus toward fulfilment" do
      send_qty(28)
      shipment = transfer.open_shipments.first

      confirm(shipment, 30)

      expect(line.reload).to be_fulfilled
      expect(line.quantity_pending_send).to eq(0)
      expect(transfer.reload.status).to eq("completed")
    end

    it "flags the shipment as arriving with more than sent" do
      send_qty(10)
      shipment = transfer.open_shipments.first
      confirm(shipment, 12)

      get admin_inventory_stock_transfer_path(transfer)

      expect(response.body).to include(I18n.t("inventory.stock_transfers.shipment_surplus"))
    end

    it "still refuses a negative count" do
      send_qty(10)
      shipment = transfer.open_shipments.first

      confirm(shipment, -3)

      expect(line.reload.quantity_received).to eq(0)
      expect(shipment.reload.status).to eq("in_transit")
    end
  end
  describe "sending more than was requested" do
    def post_send(qty, allow_overage: nil)
      params = { lines: { line.id.to_s => qty.to_s } }
      params[:allow_overage] = allow_overage unless allow_overage.nil?
      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: params
      transfer.reload
    end

    it "refuses an unconfirmed overage" do
      post_send(35)

      expect(flash[:alert]).to be_present
      expect(transfer.stock_transfer_shipments.count).to eq(0)
      expect(line.reload.quantity_sent).to eq(0)
    end

    it "accepts the overage once the sender confirms it" do
      post_send(35, allow_overage: "1")

      expect(flash[:alert]).to be_nil
      expect(transfer.open_shipments.count).to eq(1)
      expect(line.reload.quantity_sent).to eq(35)
      expect(line.quantity_open_in_transit).to eq(35)
      expect(line.quantity_pending_send).to eq(0)
    end

    it "treats anything other than the confirmed flag as unconfirmed" do
      post_send(35, allow_overage: "0")

      expect(flash[:alert]).to be_present
      expect(transfer.stock_transfer_shipments.count).to eq(0)
    end

    it "completes when the over-sent quantity arrives" do
      post_send(35, allow_overage: "1")
      confirm(transfer.open_shipments.first, 35)

      expect(line.reload.quantity_received).to eq(35)
      expect(transfer.status).to eq("completed")
      expect(IngredientLocation.find_by(location: branch, ingredient: ingredient).quantity_on_hand.to_d).to eq(35)
      expect(IngredientLocation.find_by(location: kitchen, ingredient: ingredient).quantity_on_hand.to_d).to eq(865)
    end

    it "still refuses an over-send that source stock cannot cover when restricted" do
      allow(Setting).to receive(:restrict_stock_transfers_to_source?).and_return(true)

      post_send(5000, allow_overage: "1")

      expect(flash[:alert]).to be_present
      expect(transfer.stock_transfer_shipments.count).to eq(0)
    end

    it "renders the send form wired for confirmation" do
      get admin_inventory_stock_transfer_path(transfer)

      expect(response.body).to include("transfer-overage")
      expect(response.body).to include(I18n.t("inventory.stock_transfers.confirm_overage"))
      expect(response.body).to include('data-pending="30"')
    end
  end
end
