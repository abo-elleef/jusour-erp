# frozen_string_literal: true

require "rails_helper"

RSpec.describe Order, type: :model do
  let(:user) { create(:user) }

  describe "validations" do
    it "requires order_number" do
      order = build(:order, user: user, order_number: nil)
      order.valid?
      expect(order.order_number).to be_present
    end
  end

  describe "AASM" do
    let(:order) { create(:order, user: user, status: "draft") }

    it "transitions from draft to submitted" do
      create(:order_item, order: order)
      order.recalculate_totals!
      expect { order.submit! }.to change(order, :status).from("draft").to("submitted")
    end

    it "completes from ready" do
      order.update!(status: "ready", subtotal_cents: 1000, tax_cents: 80, total_cents: 1080)
      expect { order.complete! }.to change(order, :status).to("completed")
    end
  end

  describe "#fully_paid?" do
    let(:order) { create(:order, user: user, total_cents: 1000) }

    it "returns true when payments cover total" do
      create(:payment, order: order, amount_cents: 1000, status: "completed")
      expect(order.fully_paid?).to be true
    end
  end
end
