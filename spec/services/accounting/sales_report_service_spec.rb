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

    describe "modifier breakdown" do
      def group(name, position: 0)
        ModifierGroup.create!(company: company, name: name, required: true, position: position)
      end

      def sell(order, choices, quantity: 1, unit_price_cents: 1000)
        line = create(:order_item, order: order, menu_item: menu_item, quantity: quantity, unit_price_cents: unit_price_cents)
        choices.each do |modifier|
          line.order_item_modifiers.create!(modifier: modifier, name: modifier.name,
                                            price_adjustment_cents: modifier.price_adjustment_cents)
        end
        line
      end

      let(:size) { group("Size", position: 1) }
      let(:heat) { group("Heat", position: 2) }
      let(:single) { size.modifiers.create!(company: company, name: "Single", price_adjustment_cents: 0) }
      let(:double) { size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500) }
      let(:hot) { heat.modifiers.create!(company: company, name: "Hot") }
      let(:cold) { heat.modifiers.create!(company: company, name: "Cold") }
      let(:order) do
        create(:order, user: user, company: company, status: "completed",
          subtotal_cents: 4500, total_cents: 4500, created_at: today.noon)
      end

      it "splits an item's units and revenue per choice, group by group, each adding up to the item" do
        sell(order, [single, hot], quantity: 2)
        sell(order, [double, cold])

        item = described_class.new(today, today).call[:by_item].first

        expect(item).to include(units_sold: 3, revenue_cents: 3500)
        expect(item[:modifier_groups].map { |g| g[:name] }).to eq(%w[Size Heat])

        size_group = item[:modifier_groups].first
        expect(size_group[:choices].map { |c| [c[:name], c[:units_sold], c[:revenue_cents]] })
          .to eq([["Single", 2, 2000], ["Double", 1, 1500]])
        item[:modifier_groups].each do |g|
          expect(g[:choices].sum { |c| c[:units_sold] }).to eq(3)
          expect(g[:choices].sum { |c| c[:revenue_cents] }).to eq(3500)
        end
      end

      it "merges groups and choices that share a name" do
        copy = group("Size")
        copy_double = copy.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500)
        sell(order, [double])
        sell(order, [copy_double])

        groups = described_class.new(today, today).call[:by_item].first[:modifier_groups]

        expect(groups.size).to eq(1)
        expect(groups.first[:choices]).to contain_exactly(include(name: "Double", units_sold: 2, revenue_cents: 3000))
      end

      it "puts lines with no choice in a group under a no-choice row" do
        sell(order, [single, hot])
        sell(order, [double])

        heat_group = described_class.new(today, today).call[:by_item].first[:modifier_groups].find { |g| g[:name] == "Heat" }

        expect(heat_group[:choices].map { |c| [c[:name], c[:units_sold], c[:revenue_cents], c[:no_choice]] })
          .to eq([["Hot", 1, 1000, nil], [I18n.t("accounting.sales_reports.no_choice"), 1, 1500, true]])
      end

      it "leaves items sold without modifiers with no groups" do
        sell(order, [])

        expect(described_class.new(today, today).call[:by_item].first[:modifier_groups]).to eq([])
      end
    end
  end
end
