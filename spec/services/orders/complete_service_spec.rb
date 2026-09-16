# frozen_string_literal: true

require "rails_helper"

# Paying and finishing are separate events now: money arriving leaves an order
# `submitted`, and a cashier closes it when the work is actually done.
RSpec.describe Orders::CompleteService do
  let(:company) { create(:company) }
  let(:user) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }

  before { Current.company = company }

  def order_with_items(status: "draft", **attrs)
    order = create(:order, user: user, location: location, status: status, **attrs)
    create(:order_item, order: order)
    order.recalculate_totals!
    order
  end

  describe "paying no longer closes the order" do
    it "leaves a fully paid order submitted" do
      order = order_with_items
      create(:payment, order: order, amount_cents: order.total_cents, status: "completed")

      Orders::FinalizePaidService.call(order)

      expect(order.reload.status).to eq("submitted")
      expect(order).to be_fully_paid
    end
  end

  describe ".call" do
    it "completes a submitted order" do
      order = order_with_items(status: "submitted")

      expect(described_class.call(order)).to be true
      expect(order.reload.status).to eq("completed")
    end

    it "completes an unpaid order, because pay-later is the point" do
      order = order_with_items(status: "submitted")

      expect(described_class.call(order)).to be true
      expect(order.reload).to be_completed
      expect(order.amount_due_cents).to be_positive
    end

    it "leaves a completed unpaid order on Collect Payment" do
      order = order_with_items(status: "submitted")
      described_class.call(order)

      expect(Order.not_fully_paid).to include(order.reload)
    end

    it "submits a pay-later draft on its way through" do
      order = order_with_items

      expect(described_class.call(order)).to be true
      expect(order.reload.status).to eq("completed")
    end

    it "refuses an empty cart" do
      order = create(:order, user: user, location: location)

      expect(described_class.call(order)).to be false
      expect(order.reload.status).to eq("draft")
    end

    it "refuses a cancelled order" do
      order = order_with_items(status: "cancelled")

      expect(described_class.call(order)).to be false
      expect(order.reload.status).to eq("cancelled")
    end

    it "is a no-op on an order that is already completed" do
      order = order_with_items(status: "submitted")
      described_class.call(order)

      expect(described_class.call(order)).to be false
    end

    it "skips a table order with no table number rather than raising" do
      order = order_with_items(order_type: "table")

      expect(described_class.call(order)).to be false
      expect(order.reload.status).to eq("draft")
    end
  end

  describe ".call_all" do
    it "closes every open order and reports what it skipped" do
      first  = order_with_items(status: "submitted")
      second = order_with_items(status: "ready")
      blocked = order_with_items(order_type: "table")

      result = described_class.call_all([first, second, blocked])

      expect(result.completed).to contain_exactly(first, second)
      expect(result.skipped).to eq([blocked])
      expect(first.reload).to be_completed
      expect(second.reload).to be_completed
    end

    it "does not let one unmovable order stop the rest" do
      blocked = order_with_items(order_type: "table")
      good = order_with_items(status: "submitted")

      expect { described_class.call_all([blocked, good]) }.not_to raise_error
      expect(good.reload).to be_completed
    end
  end
end
