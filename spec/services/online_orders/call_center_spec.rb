# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Call-center orders" do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:branch) do
    create(:location, company: company, public_menu_enabled: true, online_ordering_enabled: false, call_center_enabled: true)
  end
  let(:agent_role) { Role.create!(company: company, name: "Call center", key: "call_center", permissions: %w[orders:take_remote]) }
  let(:agent) { create(:user, company: company, role: "custom", role_id: agent_role.id, name: "Hoda", all_locations: true) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  def send_order(**overrides)
    OnlineOrders::SubmitService.call(location: branch, staff: agent, ip: "9.9.9.9",
                                     params: online_params(item: item, website: "", started_at: nil, **overrides))
  end

  describe OnlineOrders::SubmitService do
    it "saves a call-center request from the agent that never expires and nudges the branch later" do
      result = send_order

      expect(result).to be_ok
      req = result.request
      expect(req.channel).to eq("call_center")
      expect(req.created_by).to eq(agent)
      expect(req.expires_at).to be_nil
      expect(OnlineOrders::EscalateJob).to have_been_enqueued.with(req.id)
      expect(OnlineOrders::ExpireJob).not_to have_been_enqueued
    end

    it "works while the public menu takes no orders, but not when the branch's call-center switch is off" do
      expect(send_order).to be_ok

      branch.update!(call_center_enabled: false)
      expect(send_order.error).to eq(:closed)
    end

    it "skips the public spam guards and per-phone limits" do
      3.times { expect(send_order).to be_ok }
      expect(OnlineOrderRequest.call_center.pending.count).to eq(3)
    end

    it "still refuses a blocked customer" do
      create(:customer, company: company, phone: "01001234567", blocked_at: Time.current)

      expect(send_order.error).to eq(:blocked)
    end
  end

  it "keeps waiting forever and becomes late after a few minutes" do
    req = send_order.request

    travel 2.hours do
      expect(OnlineOrderRequest.waiting).to include(req)
      expect(req.overdue?).to be(false)
      expect(req.late?).to be(true)
    end
  end

  it "doesn't flag the call-center room as a shared device" do
    send_order(phone: "01001111111")
    req = send_order(phone: "01002222222").request

    expect(OnlineOrders::CustomerCheck.new(req).reasons).not_to include(:shared_device)
  end

  describe OnlineOrders::AcceptService do
    it "makes a call-center order owned by the cashier, naming the agent" do
      order = described_class.call(request: send_order(note: "no onions").request, user: cashier).order.reload

      expect(order.user).to eq(cashier)
      expect(order.source).to eq("call_center")
      expect(order.notes).to include("Hoda").and include("no onions")
    end
  end

  describe OnlineOrders::CancelService do
    it "lets the agent who sent it cancel while it waits, and only then" do
      req = send_order.request

      expect(described_class.call(request: req, user: cashier)).to be(false)
      expect(described_class.call(request: req, user: agent)).to be_truthy
      expect(req.reload).to be_cancelled
      expect(req.decided_by).to eq(agent)
      expect(described_class.call(request: req, user: agent)).to be(false)
      expect(OnlineOrders::AcceptService.call(request: req, user: cashier).error).to eq(:not_pending)
    end

    it "can't cancel once a cashier accepted" do
      req = send_order.request
      OnlineOrders::AcceptService.call(request: req, user: cashier)

      expect(described_class.call(request: req.reload, user: agent)).to be(false)
      expect(req.reload).to be_accepted
    end
  end

  describe OnlineOrders::EscalateJob do
    it "rings the branch again and schedules the next nudge while it waits" do
      req = send_order.request
      clear_enqueued_jobs

      expect(OnlineOrders::Broadcast).to receive(:inbox).with(req.location, nudge: true)
      described_class.perform_now(req.id)
      expect(described_class).to have_been_enqueued.with(req.id, 2)
    end

    it "stops once the request is decided" do
      req = send_order.request
      OnlineOrders::CancelService.call(request: req, user: agent)
      clear_enqueued_jobs

      expect(OnlineOrders::Broadcast).not_to receive(:inbox)
      described_class.perform_now(req.id)
      expect(described_class).not_to have_been_enqueued
    end
  end
end
