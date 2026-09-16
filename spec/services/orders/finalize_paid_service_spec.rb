# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::FinalizePaidService do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:order) do
    create(:order, user: user, status: "draft", order_type: "pickup", subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
  end

  before do
    create(:order_item, order: order)
    create(:payment, order: order, amount_cents: 1000, status: "completed")
    order.reload
  end

  it "sends a paid draft to the kitchen" do
    expect {
      described_class.call(order)
    }.to have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)

    expect(order.reload.status).to eq("submitted")
  end

  # The change that this spec exists to pin down: being paid for is not being
  # finished. A cashier closes the order, through Orders::CompleteService.
  it "does not complete the order" do
    described_class.call(order)

    expect(order.reload).not_to be_completed
  end

  it "leaves the receipt to the payment flow, which knows the money has landed" do
    expect {
      described_class.call(order)
    }.not_to have_enqueued_job(Printing::PrintReceiptJob)
  end

  it "does nothing for an order that is still short" do
    order.payments.destroy_all
    create(:payment, order: order, amount_cents: 400, status: "completed")

    described_class.call(order)

    expect(order.reload.status).to eq("draft")
  end
end
