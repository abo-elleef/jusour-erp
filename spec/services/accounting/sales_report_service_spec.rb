# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::SalesReportService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:category) { create(:category, company: company, name: "Mains") }
  let(:menu_item) { create(:menu_item, company: company, category: category, base_price_cents: 1000) }
  let(:today) { Date.current }

  before { Current.company = company }

  describe "#call" do
    it "calculates net sales from subtotal minus discounts and refunds" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 2000, discount_cents: 200, tax_cents: 100, tip_cents: 50, total_cents: 1950,
        created_at: today.noon)
      create(:order_item, order: order, menu_item: menu_item, quantity: 2, unit_price_cents: 1000)
      create(:payment, order: order, amount_cents: 1950, status: "partially_refunded", refunded_amount_cents: 500)

      report = described_class.new(today, today).call

      expect(report[:summary][:gross_sales_cents]).to eq(2000)
      expect(report[:summary][:discount_cents]).to eq(200)
      expect(report[:summary][:refunds_cents]).to eq(500)
      expect(report[:summary][:net_sales_cents]).to eq(1300)
    end

    it "tracks promo cost separately within discounts" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 2000, discount_cents: 500, tax_cents: 0, tip_cents: 0, total_cents: 1500,
        created_at: today.noon)
      item = create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: 2000)
      promo = create(:menu_promo, company: company, menu_item: menu_item, promo_price_cents: 500)
      order.order_discounts.create!(
        menu_promo: promo,
        order_item: item,
        description: "Promo: Test",
        amount_cents: 500
      )

      report = described_class.new(today, today).call

      expect(report[:summary][:discount_cents]).to eq(500)
      expect(report[:summary][:promo_cost_cents]).to eq(500)
    end

    it "charts daily net sales instead of order totals with tax and tips" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 1000, discount_cents: 0, tax_cents: 80, tip_cents: 100, total_cents: 1180,
        created_at: today.noon)
      create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: 1000)

      report = described_class.new(today, today).call

      expect(report[:daily_totals][today]).to eq(1000)
      expect(report[:daily_totals][today]).not_to eq(1180)
    end

    it "assigns a post-midnight order to the previous operating day (default 6 AM cutoff)" do
      one_am = today.beginning_of_day + 1.hour # 01:00 on `today` → operating day is yesterday
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 500, discount_cents: 0, tax_cents: 0, tip_cents: 0, total_cents: 500,
        created_at: one_am)
      create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: 500)

      yesterday = today - 1
      report = described_class.new(yesterday, today).call
      expect(report[:daily_totals][yesterday]).to eq(500) # counted the night before
      expect(report[:daily_totals][today].to_i).to eq(0)  # not the calendar day it was placed

      # A report scoped to `today` alone excludes the 1 AM order entirely.
      expect(described_class.new(today, today).call[:summary][:net_sales_cents]).to eq(0)
    end

    it "includes modifier revenue in category breakdown" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 1200, discount_cents: 0, tax_cents: 0, total_cents: 1200, created_at: today.noon)
      item = create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: 1000)
      group = ModifierGroup.create!(company: company, name: "Extras")
      modifier = group.modifiers.create!(name: "Extra cheese", price_adjustment_cents: 200)
      item.order_item_modifiers.create!(modifier: modifier, name: modifier.name, price_adjustment_cents: 200)

      report = described_class.new(today, today).call
      mains = report[:by_category].find { |row| row[:category] == "Mains" }

      expect(mains[:revenue_cents]).to eq(1200)
    end

    it "lists each item with its category, units and revenue" do
      other = create(:menu_item, company: company, category: category, base_price_cents: 500, name: "Fries")
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 2500, total_cents: 2500, created_at: today.noon)
      create(:order_item, order: order, menu_item: menu_item, quantity: 2, unit_price_cents: 1000)
      create(:order_item, order: order, menu_item: other, quantity: 1, unit_price_cents: 500)

      items = described_class.new(today, today).call[:by_item]

      expect(items.map { |r| r[:name] }).to eq([menu_item.name, "Fries"])
      expect(items.first).to include(category: "Mains", units_sold: 2, revenue_cents: 2000)
      expect(items.last).to include(units_sold: 1, revenue_cents: 500)
    end
  end
end
