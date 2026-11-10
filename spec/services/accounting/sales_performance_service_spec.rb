# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::SalesPerformanceService do
  let(:company) { create(:company) }
  let(:cashier) { create(:user, company: company, name: "Amal") }
  let(:other_cashier) { create(:user, company: company, name: "Bassem") }
  let(:branch_a) { create(:location, company: company, name: "Maadi") }
  let(:branch_b) { create(:location, company: company, name: "Zamalek") }
  let(:today) { Date.current }

  before { Current.company = company }

  def sale(user:, location:, type: "pickup", subtotal: 1000, discount: 0, status: "completed")
    create(:order, user: user, company: company, location: location, order_type: type, status: status,
                   subtotal_cents: subtotal, discount_cents: discount, total_cents: subtotal - discount,
                   created_at: today.noon)
  end

  def service(**opts) = described_class.new(today, today, **opts)

  describe "#by_branch" do
    it "splits net sales per branch and order type, and ignores non-completed orders" do
      sale(user: cashier, location: branch_a, type: "table", subtotal: 2000, discount: 200)
      sale(user: cashier, location: branch_a, type: "delivery", subtotal: 1000)
      sale(user: cashier, location: branch_b, type: "pickup", subtotal: 500)
      sale(user: cashier, location: branch_b, subtotal: 9999, status: "cancelled")

      rows, totals = service.by_branch(sort: "name", direction: "asc")

      expect(rows.map(&:name)).to eq(%w[Maadi Zamalek])
      maadi = rows.first
      expect(maadi.orders).to eq(2)
      expect(maadi.net_cents).to eq(2800)
      expect(maadi.by_type["table"]).to eq(orders: 1, net_cents: 1800)
      expect(maadi.by_type["delivery"]).to eq(orders: 1, net_cents: 1000)
      expect(maadi.by_type["pickup"]).to eq(orders: 0, net_cents: 0)
      expect(maadi.avg_ticket_cents).to eq(1400)
      expect(totals[:net_cents]).to eq(3300)
      expect(totals[:orders]).to eq(3)
    end

    it "agrees with the Sales report on net sales" do
      sale(user: cashier, location: branch_a, subtotal: 2000, discount: 200)
      sale(user: cashier, location: branch_b, subtotal: 700)

      _, totals = service.by_branch
      report = Accounting::SalesReportService.new(today, today).call

      expect(totals[:net_cents]).to eq(report[:summary][:net_sales_cents])
    end

    it "filters to one branch" do
      sale(user: cashier, location: branch_a, subtotal: 2000)
      sale(user: cashier, location: branch_b, subtotal: 700)

      rows, totals = service(location_id: branch_b.id).by_branch

      expect(rows.map(&:name)).to eq(["Zamalek"])
      expect(totals[:net_cents]).to eq(700)
    end

    it "sorts by net sales, biggest first by default" do
      sale(user: cashier, location: branch_a, subtotal: 100)
      sale(user: cashier, location: branch_b, subtotal: 900)

      rows, = service.by_branch

      expect(rows.map(&:name)).to eq(%w[Zamalek Maadi])
    end

    it "falls back to the default sort on an unknown key" do
      sale(user: cashier, location: branch_a, subtotal: 100)
      expect { service.by_branch(sort: "DROP TABLE") }.not_to raise_error
    end
  end

  describe "#by_cashier" do
    it "reports sales, discount rate, and the voids and refunds each person performed" do
      order = sale(user: cashier, location: branch_a, subtotal: 2000, discount: 500)
      sale(user: cashier, location: branch_a, subtotal: 1000)
      voided = sale(user: cashier, location: branch_a, subtotal: 800, status: "cancelled")
      voided.order_events.create!(event_type: "void", user: other_cashier, description: "Wrong order")
      order.order_events.create!(event_type: "refund", user: other_cashier,
                                 description: "Refunded 300 cents: cold food")

      rows = service.by_cashier(sort: "name", direction: "asc")
      amal = rows.find { |r| r.name == "Amal" }
      bassem = rows.find { |r| r.name == "Bassem" }

      expect(amal.orders).to eq(2)
      expect(amal.net_cents).to eq(2500)
      expect(amal.avg_ticket_cents).to eq(1250)
      expect(amal.discount_rate).to be_within(0.01).of(500 * 100.0 / 3000)
      expect(amal.voids).to eq(0)
      # Bassem rang up nothing but still appears: the voids and the refund are his.
      expect(bassem.orders).to eq(0)
      expect(bassem.voids).to eq(1)
      expect(bassem.refunds).to eq(1)
    end
  end

  describe "#exceptions" do
    it "lists voids and refunds with amounts and sums them against gross sales" do
      order = sale(user: cashier, location: branch_a, subtotal: 2000)
      voided = sale(user: cashier, location: branch_b, subtotal: 800, status: "cancelled")
      voided.order_events.create!(event_type: "void", user: other_cashier, description: "Wrong order")
      order.order_events.create!(event_type: "refund", user: other_cashier, description: "Refunded 300 cents: cold food")
      order.order_events.create!(event_type: "note", user: other_cashier, description: "ignored")

      events = service.exceptions.to_a
      summary = service.exceptions_summary

      expect(events.map(&:event_type)).to match_array(%w[void refund])
      expect(events.find { |e| e.event_type == "void" }.amount_cents).to eq(800)
      expect(events.find { |e| e.event_type == "refund" }.amount_cents).to eq(300)
      expect(summary[:void]).to eq(count: 1, cents: 800)
      expect(summary[:refund]).to eq(count: 1, cents: 300)
      expect(summary[:lost_pct]).to be_within(0.01).of(1100 * 100.0 / 2000)
    end

    it "filters by kind and branch" do
      voided = sale(user: cashier, location: branch_a, subtotal: 800, status: "cancelled")
      voided.order_events.create!(event_type: "void", user: other_cashier, description: "x")
      elsewhere = sale(user: cashier, location: branch_b, subtotal: 400, status: "cancelled")
      elsewhere.order_events.create!(event_type: "void", user: other_cashier, description: "y")

      expect(service.exceptions(kind: "refund").to_a).to be_empty
      expect(service(location_id: branch_a.id).exceptions(kind: "void").map(&:order_id)).to eq([voided.id])
    end

    it "excludes events outside the date range" do
      order = sale(user: cashier, location: branch_a, status: "cancelled")
      order.order_events.create!(event_type: "void", user: other_cashier, description: "old", created_at: 10.days.ago)

      expect(service.exceptions.to_a).to be_empty
    end
  end
end
