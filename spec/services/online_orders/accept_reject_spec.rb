# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accepting and rejecting online orders" do
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:branch) { online_branch(company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let(:area) { branch.delivery_areas.create!(company: company, name: "Dokki", fee_cents: 1_500) }
  let(:request) do
    OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item, area: area, note: "ring twice")).request
  end

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  describe OnlineOrders::AcceptService do
    it "builds a placed online order owned by the cashier, with the fee, and creates the customer" do
      result = described_class.call(request: request, user: cashier)

      order = result.order.reload
      expect(order.user).to eq(cashier)
      expect(order.source).to eq("online")
      expect(order.order_type).to eq("delivery")
      expect(order.status).to eq("submitted")
      expect(order.order_number).to be_present
      expect(order.delivery_fee_cents).to eq(1_500)
      expect(order.subtotal_cents).to eq(10_000)
      expect(order.notes).to include("ring twice")
      expect(order.customer.phone).to eq("01001234567")
      expect(order.customer.addresses.pluck(:address)).to eq(["12 Nile St, flat 4"])
      expect(request.reload).to be_accepted
      expect(request.decided_by).to eq(cashier)
      expect(Printing::DispatchProductionPrintsJob).to have_been_enqueued.with(order.id)
    end

    it "accepts only once" do
      described_class.call(request: request, user: cashier)

      expect(described_class.call(request: request.reload, user: cashier).error).to eq(:not_pending)
      expect(Order.where(source: "online").count).to eq(1)
    end

    it "asks to confirm when prices moved, then accepts at the new total" do
      request
      item.update!(base_price_cents: 6_000)

      first = described_class.call(request: request, user: cashier)
      expect(first.error).to eq(:price_changed)
      expect(first.new_total_cents).to eq(12_000 + 1_500)
      expect(Order.count).to eq(0)

      expect(described_class.call(request: request, user: cashier, confirm_price_change: true)).to be_ok
    end

    it "refuses an expired request" do
      request.update!(expires_at: 1.minute.ago)

      expect(described_class.call(request: request, user: cashier).error).to eq(:expired)
    end
  end

  describe OnlineOrders::RejectService do
    it "rejects with a reason and can block the phone" do
      expect(described_class.call(request: request, user: cashier, reason: "suspicious", block: true)).to be(true)

      expect(request.reload).to be_rejected
      expect(request.reject_reason).to eq("suspicious")
      customer = Customer.find_by(phone: "01001234567")
      expect(customer).to be_blocked
      expect(customer.blocked_by).to eq(cashier)
    end

    it "does nothing to a request already decided" do
      OnlineOrders::AcceptService.call(request: request, user: cashier)

      expect(described_class.call(request: request.reload, user: cashier, reason: "other")).to be(false)
    end
  end

  describe OnlineOrders::ExpireJob do
    it "expires a request that is still waiting after its deadline" do
      request.update!(expires_at: 1.minute.ago)

      described_class.perform_now(request.id)

      expect(request.reload).to be_expired
    end

    it "leaves an accepted request alone" do
      OnlineOrders::AcceptService.call(request: request, user: cashier)
      request.reload.update_column(:expires_at, 1.minute.ago)

      described_class.perform_now(request.id)

      expect(request.reload).to be_accepted
    end
  end
end
