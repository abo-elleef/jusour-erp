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

    it "charts daily net sales instead of order totals with tax and tips" do
      order = create(:order, user: user, company: company, status: "completed",
        subtotal_cents: 1000, discount_cents: 0, tax_cents: 80, tip_cents: 100, total_cents: 1180,
        created_at: today.noon)
      create(:order_item, order: order, menu_item: menu_item, quantity: 1, unit_price_cents: 1000)

      report = described_class.new(today, today).call

      expect(report[:daily_totals][today]).to eq(1000)
      expect(report[:daily_totals][today]).not_to eq(1180)
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
  end
end
