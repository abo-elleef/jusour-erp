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

  it "submits, completes, and enqueues printing jobs for a paid draft order" do
    expect {
      described_class.call(order)
    }.to have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)
      .and have_enqueued_job(Printing::PrintReceiptJob).with(order.id)

    expect(order.reload.status).to eq("completed")
  end
end
