# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reverting a received shipment", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, name: "Tomatoes",
      quantity_on_hand: 900, cost_per_unit_cents: 100)
  end
  let(:transfer) do
    create(:stock_transfer, company: company, from_location: kitchen, to_location: branch,
      requested_by: owner)
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

  def on_hand(location)
    IngredientLocation.find_by(location: location, ingredient: ingredient)&.quantity_on_hand.to_d
  end

  def send_and_receive(qty)
    ::Inventory::SendStockTransferService.new(
      transfer, owner, line_quantities: { line.id.to_s => qty.to_s }
    ).call
    shipment = transfer.reload.open_shipments.first
    post confirm_receipt_admin_inventory_stock_transfer_path(transfer),
      params: { shipment_id: shipment.id, lines: { line.id.to_s => qty.to_s } }
    shipment.reload
  end

  def revert(shipment, reason: "sent twice by mistake")
    post revert_shipment_admin_inventory_stock_transfer_path(transfer),
      params: { shipment_id: shipment.id, revert_reason: reason }
    transfer.reload
  end

  describe "balances" do
    it "puts the goods back at the source and takes them off the destination" do
      shipment = send_and_receive(10)

      expect(on_hand(kitchen)).to eq(890)
      expect(on_hand(branch)).to eq(10)

      revert(shipment)

      expect(on_hand(kitchen)).to eq(900)
      expect(on_hand(branch)).to eq(0)
      expect(shipment.reload.status).to eq("reverted")
    end

    it "returns the stock at the cost it left with, not the master cost" do
      # Source batch is dearer than the ingredient's standard cost, so the two
      # would be distinguishable if the reversal used the wrong one.
      StockBatch.where(ingredient: ingredient, location: kitchen).update_all(cost_per_unit_cents: 250)
      shipment = send_and_receive(10)

      revert(shipment)

      returned = StockBatch.find_by(ingredient: ingredient, location: kitchen,
        batch_reference: "XFER-#{transfer.transfer_number}-#{shipment.sequence}-REV")
      expect(returned).to be_present
      expect(returned.cost_per_unit_cents).to eq(250)
      expect(returned.quantity_remaining.to_d).to eq(10)
    end

    it "empties the batch the receipt created rather than some other batch" do
      # Destination already holds older stock, which must be left alone.
      create(:ingredient_location, location: branch, ingredient: ingredient, quantity_on_hand: 5)
      StockBatch.create!(ingredient: ingredient, location: branch, quantity_received: 5,
        quantity_remaining: 5, cost_per_unit_cents: 70, received_on: Date.current - 10)
      shipment = send_and_receive(10)

      revert(shipment)

      arrival = StockBatch.find_by(ingredient: ingredient, location: branch,
        batch_reference: "XFER-#{transfer.transfer_number}-#{shipment.sequence}")
      older = StockBatch.find_by(ingredient: ingredient, location: branch, cost_per_unit_cents: 70)
      expect(arrival.reload.quantity_remaining.to_d).to eq(0)
      expect(older.reload.quantity_remaining.to_d).to eq(5)
      expect(on_hand(branch)).to eq(5)
    end

    it "leaves an audit trail on both sides" do
      shipment = send_and_receive(10)

      revert(shipment)

      out = StockAdjustment.where(stock_transfer: transfer, location: branch, quantity_delta: -10)
      into = StockAdjustment.where(stock_transfer: transfer, location: kitchen, quantity_delta: 10)
      expect(out).to be_present
      expect(into).to be_present
      expect(shipment.reload.reverted_by).to eq(owner)
      expect(shipment.reverted_reason).to eq("sent twice by mistake")
    end
  end

  describe "the transfer afterwards" do
    it "rolls both totals back so the sender can send again" do
      shipment = send_and_receive(10)
      expect(line.reload.quantity_sent).to eq(10)
      expect(line.quantity_received).to eq(10)

      revert(shipment)

      expect(line.reload.quantity_sent).to eq(0)
      expect(line.quantity_received).to eq(0)
      expect(line.quantity_pending_send).to eq(30)
      expect(transfer.can_send?).to be true
    end

    it "reverting one of two shipments leaves the other alone" do
      first = send_and_receive(10)
      second = send_and_receive(6)

      revert(second)

      expect(first.reload.status).to eq("received")
      expect(second.reload.status).to eq("reverted")
      expect(line.reload.quantity_received).to eq(10)
      expect(on_hand(branch)).to eq(10)
      expect(on_hand(kitchen)).to eq(890)
    end
  end

  describe "guards" do
    it "refuses without a reason, moving nothing" do
      shipment = send_and_receive(10)

      revert(shipment, reason: "  ")

      expect(flash[:alert]).to be_present
      expect(shipment.reload.status).to eq("received")
      expect(on_hand(branch)).to eq(10)
    end

    it "refuses a shipment that is still in transit" do
      ::Inventory::SendStockTransferService.new(
        transfer, owner, line_quantities: { line.id.to_s => "10" }
      ).call
      shipment = transfer.reload.open_shipments.first

      revert(shipment)

      expect(flash[:alert]).to be_present
      expect(shipment.reload.status).to eq("in_transit")
    end

    it "cannot be reverted twice" do
      shipment = send_and_receive(10)
      revert(shipment)

      revert(shipment)

      expect(flash[:alert]).to be_present
      # The second attempt moved nothing.
      expect(on_hand(kitchen)).to eq(900)
      expect(on_hand(branch)).to eq(0)
    end

    it "refuses a shipment belonging to another transfer" do
      shipment = send_and_receive(10)
      other = create(:stock_transfer, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)

      post revert_shipment_admin_inventory_stock_transfer_path(other),
        params: { shipment_id: shipment.id, revert_reason: "x" }

      expect(flash[:alert]).to be_present
      expect(shipment.reload.status).to eq("received")
    end
  end

  # The situation that prompted this: goods arrived, were used, and only then was
  # the double-send noticed. A correction must still be possible.
  describe "when the destination already used the goods" do
    it "still reverts, and says the destination is now negative" do
      shipment = send_and_receive(10)
      # Branch consumes what arrived.
      StockAdjustment.create!(ingredient: ingredient, user: owner, location: branch,
        quantity_delta: -10, adjustment_type: "consumption")
      expect(on_hand(branch)).to eq(0)

      revert(shipment)

      expect(shipment.reload.status).to eq("reverted")
      expect(on_hand(kitchen)).to eq(900)
      expect(on_hand(branch)).to eq(-10)
      expect(flash[:notice]).to include("Tomatoes")
    end
  end

  describe "the page" do
    it "offers revert on a received shipment only" do
      shipment = send_and_receive(10)

      get admin_inventory_stock_transfer_path(transfer)
      expect(response.body).to include(I18n.t("inventory.stock_transfers.revert_shipment"))

      revert(shipment)

      get admin_inventory_stock_transfer_path(transfer)
      expect(response.body).to include(I18n.t("inventory.stock_transfers.shipment_statuses.reverted"))
      expect(response.body).to include("sent twice by mistake")
      expect(response.body).not_to include(I18n.t("inventory.stock_transfers.revert_shipment"))
    end
  end

  # The root cause of the incident: the send form was submitted twice.
  describe "preventing a double send" do
    def post_send(token: nil, qty: 10)
      params = { lines: { line.id.to_s => qty.to_s } }
      params[:send_token] = token if token
      post send_transfer_admin_inventory_stock_transfer_path(transfer), params: params
      transfer.reload
    end

    it "creates one shipment when the same form is posted twice" do
      token = SecureRandom.uuid

      post_send(token: token)
      post_send(token: token)

      expect(transfer.stock_transfer_shipments.count).to eq(1)
      expect(line.reload.quantity_sent).to eq(10)
      # Not an error the user has to make sense of — the first click worked.
      expect(flash[:alert]).to be_nil
      expect(flash[:notice]).to eq(I18n.t("flash.stock_transfer.sent"))
    end

    it "still allows a deliberate second send, which carries a fresh token" do
      post_send(token: SecureRandom.uuid)
      post_send(token: SecureRandom.uuid, qty: 6)

      expect(transfer.stock_transfer_shipments.count).to eq(2)
      expect(line.reload.quantity_sent).to eq(16)
    end

    it "renders a fresh token on the form each time" do
      get admin_inventory_stock_transfer_path(transfer)
      first = response.body[/name="send_token"[^>]*value="([^"]+)"/, 1]

      get admin_inventory_stock_transfer_path(transfer)
      second = response.body[/name="send_token"[^>]*value="([^"]+)"/, 1]

      expect(first).to be_present
      expect(second).to be_present
      expect(first).not_to eq(second)
    end

    it "guards the form in the browser as well as on the server" do
      get admin_inventory_stock_transfer_path(transfer)

      expect(response.body).to include("submit-once")
      # Listed last, so the overage confirmation's deliberate re-submit is not
      # mistaken for a double click.
      action = response.body[/action="(submit-&gt;transfer-overage#confirm[^"]*)"/, 1].to_s
      expect(action).to include("transfer-overage#confirm")
      expect(action.index("submit-once#guard")).to be > action.index("transfer-overage#confirm")
    end
  end
end
