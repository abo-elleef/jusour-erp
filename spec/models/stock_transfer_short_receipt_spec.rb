# frozen_string_literal: true

require "rails_helper"

# When a shipment is confirmed short, the units that never arrived must go back to
# "still to send". Measuring pending-send against quantity_sent instead of
# quantity_received left the line looking fully dispatched while the destination had
# nothing, and the send table rendered no rows — the sender was stuck.
RSpec.describe "Stock transfer with a short receipt", type: :model do
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
    create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 500)
    StockBatch.create!(ingredient: ingredient, location: kitchen, quantity_received: 500,
      quantity_remaining: 500, cost_per_unit_cents: 100, received_on: Date.current)
  end

  def send_all(qty)
    ::Inventory::SendStockTransferService.new(
      transfer, owner, line_quantities: { line.id.to_s => qty.to_s }
    ).call
  end

  def confirm(qty)
    ::Inventory::ConfirmStockTransferService.new(
      transfer, owner, line_quantities: { line.id.to_s => qty.to_s }
    ).call
  end

  it "starts with everything to send" do
    expect(line.quantity_pending_send).to eq(24)
  end

  it "counts an open shipment as in transit, not still to send" do
    send_all(24)

    expect(line.reload.quantity_open_in_transit).to eq(24)
    expect(line.quantity_pending_send).to eq(0)
  end

  it "releases the shortfall back to pending when the receipt is short" do
    send_all(24)
    confirm(0)          # nothing arrived
    line.reload

    expect(line.quantity_received).to eq(0)
    expect(line.quantity_open_in_transit).to eq(0)   # the shipment is closed
    expect(line.quantity_pending_send).to eq(24)     # so it can be sent again
  end

  it "releases only the missing part of a partial receipt" do
    send_all(24)
    confirm(18)
    line.reload

    expect(line.quantity_received).to eq(18)
    expect(line.quantity_pending_send).to eq(6)
  end

  it "lets the sender actually dispatch the shortfall again" do
    send_all(24)
    confirm(0)

    expect { send_all(24) }.not_to raise_error
    expect(line.reload.quantity_open_in_transit).to eq(24)
    expect(line.quantity_pending_send).to eq(0)
  end

  it "settles to zero once the full quantity has been received" do
    send_all(24)
    confirm(0)
    send_all(24)
    confirm(24)
    line.reload

    expect(line.quantity_received).to eq(24)
    expect(line.quantity_pending_send).to eq(0)
    expect(line).to be_fulfilled
    expect(transfer.reload.status).to eq("completed")
  end

  it "leaves the transfer sendable after a short receipt" do
    send_all(24)
    confirm(0)

    expect(transfer.reload.status).to eq("partially_received")
    expect(transfer.can_send?).to be(true)
  end

  it "stops reporting closed shipments as in transit" do
    send_all(24)
    confirm(0)

    # sent(24) - received(0) would still read 24 as bare arithmetic.
    expect(line.reload.quantity_in_transit).to eq(0)
  end

  it "moves value at the same unit cost on both sides of the transfer" do
    StockBatch.where(ingredient: ingredient, location: kitchen).update_all(cost_per_unit_cents: 300)
    StockBatch.create!(ingredient: ingredient, location: kitchen, quantity_received: 10,
      quantity_remaining: 10, cost_per_unit_cents: 100, received_on: Date.current - 1)

    send_all(24)
    confirm(24)

    out = StockAdjustment.find_by(stock_transfer: transfer, adjustment_type: "transfer_out")
    arrived = StockAdjustment.find_by(stock_transfer: transfer, adjustment_type: "transfer_in")
    # FIFO: 10 x 100 + 14 x 300 = 5200 / 24
    expect(out.unit_cost_cents).to eq(217)
    expect(arrived.unit_cost_cents).to eq(217)
  end
end
