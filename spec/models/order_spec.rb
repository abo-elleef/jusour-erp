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

  describe "order numbering" do
    let(:branch) { create(:location) }
    let(:other_branch) { create(:location) }

    it "restarts at 1 for each branch on each business day" do
      first  = create(:order, user: user, location: branch)
      second = create(:order, user: user, location: branch)

      expect([first.order_number, second.order_number]).to eq(%w[1 2])
      expect(first.business_date).to eq(BusinessDay.for(Time.current, location: branch))
    end

    it "numbers each branch independently on the same day" do
      create(:order, user: user, location: branch)
      elsewhere = create(:order, user: user, location: other_branch)

      expect(elsewhere.order_number).to eq("1")
    end

    it "starts over on the next business day" do
      create(:order, user: user, location: branch)
      tomorrow = create(:order, user: user, location: branch,
                                business_date: BusinessDay.for(Time.current, location: branch) + 1)

      expect(tomorrow.order_number).to eq("1")
    end

    it "allows the same number on another branch-day" do
      create(:order, user: user, location: branch, order_number: "7")
      duplicate = build(:order, user: user, location: other_branch, order_number: "7")

      expect(duplicate).to be_valid
    end

    it "rejects the same number twice on one branch-day" do
      first = create(:order, user: user, location: branch, order_number: "7")
      duplicate = build(:order, user: user, location: branch,
                                business_date: first.business_date, order_number: "7")

      expect(duplicate).not_to be_valid
    end
  end

  describe ".not_fully_paid" do
    let(:order) { create(:order, user: user, total_cents: 1000) }

    before { create(:order_item, order: order) }

    it "includes a draft that has been part paid" do
      create(:payment, order: order, amount_cents: 400, status: "completed")
      expect(Order.not_fully_paid).to include(order)
    end

    it "includes a draft that has not been paid at all" do
      expect(Order.not_fully_paid).to include(order)
    end

    it "excludes a fully paid order" do
      create(:payment, order: order, amount_cents: 1000, status: "completed")
      expect(Order.not_fully_paid).not_to include(order)
    end

    it "excludes a cancelled order" do
      order.update!(status: "cancelled")
      expect(Order.not_fully_paid).not_to include(order)
    end

    it "excludes an empty cart" do
      empty = create(:order, user: user, total_cents: 1000)
      expect(Order.not_fully_paid).not_to include(empty)
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
