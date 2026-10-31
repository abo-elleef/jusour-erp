# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Valued inventory reports" do
  let(:kitchen) { create(:location, :central_kitchen) }
  let(:branch) { create(:location) }
  let(:category) { create(:ingredient_category) }
  let(:flour) { create(:ingredient, ingredient_category: category, quantity_on_hand: 0, cost_per_unit_cents: 100) }
  let(:user) { create(:user, :owner, company: Current.company) }
  let(:start_date) { Date.new(2026, 10, 1) }
  let(:end_date) { Date.new(2026, 10, 31) }

  def move(delta, type, cost, at:, loc: kitchen, ingredient: flour)
    adj = StockAdjustment.create!(ingredient: ingredient, user: user, location: loc, quantity_delta: delta,
      adjustment_type: type, unit_cost_cents: cost)
    adj.update_columns(created_at: at)
    adj
  end

  describe Inventory::Reports::ItemCardService do
    before do
      move(10, "vendor_invoice", 100, at: Time.zone.local(2026, 9, 20))
      move(20, "vendor_invoice", 160, at: Time.zone.local(2026, 10, 5))
      move(-6, "consumption", 140, at: Time.zone.local(2026, 10, 10))
      move(4, "vendor_invoice", 999, at: Time.zone.local(2026, 11, 2))
    end

    let(:service) { described_class.new(start_date: start_date, end_date: end_date, ingredient: flour) }

    it "opens from everything before the period and closes from the period" do
      totals = service.totals

      expect(totals.opening_qty).to eq(10)
      expect(totals.opening_value).to eq(1000)
      expect([totals.qty_in, totals.qty_out, totals.closing_qty]).to eq([20, 6, 24])
      expect([totals.value_in, totals.value_out]).to eq([3200, 840])
      # closing valued at the cost of the latest movement then (140), not at the
      # sum of movement values
      expect(totals.closing_value).to eq(24 * 140)
    end

    it "carries the running balance from the opening, oldest first" do
      expect(service.movements.map { |row| row.running_qty.to_d }).to eq([30, 24])
    end

    it "folds to one line per item without an item" do
      row = described_class.new(start_date: start_date, end_date: end_date).summaries.sole
      expect([row.ingredient, row.opening_qty, row.closing_qty]).to eq([flour, 10, 24])
    end
  end

  describe Inventory::Reports::AdjustmentsService do
    it "values surpluses and deficits separately and ignores non-adjustment types" do
      move(5, "cycle_count_correction", 200, at: Time.zone.local(2026, 10, 3))
      move(-2, "cycle_count_correction", 150, at: Time.zone.local(2026, 10, 4))
      move(-3, "manual_remove", 150, at: Time.zone.local(2026, 10, 6))
      move(-9, "consumption", 150, at: Time.zone.local(2026, 10, 6))

      result = described_class.new(start_date: start_date, end_date: end_date,
        types: described_class::DEFAULT_TYPES).call

      expect(result.surplus_cents).to eq(1000)
      expect(result.deficit_cents).to eq(750)
      expect(result.net_cents).to eq(250)
      expect(result.deficit.sole.quantity).to eq(5)
    end

    it "falls back to the default types for an unknown selection" do
      expect(described_class.normalize_types(%w[transfer_out])).to eq(described_class::DEFAULT_TYPES)
    end
  end

  describe Inventory::Reports::StockLevelsService do
    def level(ingredient, on_hand:, min:, max:)
      ingredient.ingredient_locations.create!(location: branch, quantity_on_hand: on_hand,
        reorder_threshold: min, max_quantity: max)
    end

    it "orders a low item up to its maximum" do
      level(flour, on_hand: 3, min: 5, max: 20)
      row = described_class.new(location: branch).call.sole

      expect(row.status).to eq("below_min")
      expect([row.target_basis, row.order_quantity]).to eq(["max", 17])
    end

    it "without a maximum, orders to the minimum plus cover days of usage" do
      move(-30, "clear_all_stock", 100, at: 3.days.ago, loc: branch)
      # set after the movement, which moves on-hand itself
      flour.ingredient_locations.find_by!(location: branch)
        .update!(quantity_on_hand: 2, reorder_threshold: 5, max_quantity: 0)

      row = described_class.new(location: branch, cover_days: 7).call.sole

      # 30 used over the 30-day window = 1/day; target 5 + 7
      expect([row.target_basis, row.target, row.order_quantity]).to eq(["usage", 12, 10])
    end

    it "orders from zero when on hand is negative" do
      level(flour, on_hand: -500, min: 5, max: 20)
      expect(described_class.new(location: branch).call.sole.order_quantity).to eq(20)
    end

    it "flags an item with no levels set" do
      level(flour, on_hand: 2, min: 0, max: 0)
      expect(described_class.new(location: branch).call.sole.status).to eq("no_levels")
    end
  end

  describe Inventory::Reports::StagnantItemsService do
    let(:sugar) { create(:ingredient, ingredient_category: category, quantity_on_hand: 0) }

    before do
      flour.ingredient_locations.create!(location: kitchen, quantity_on_hand: 10)
      sugar.ingredient_locations.create!(location: kitchen, quantity_on_hand: 4)
      move(-1, "consumption", 100, at: 3.days.ago)
      # a count surplus is not use
      move(2, "cycle_count_correction", 100, at: 2.days.ago, ingredient: sugar)
      move(-1, "consumption", 100, at: 60.days.ago, ingredient: sugar)
    end

    it "lists items with stock that nothing used within the window" do
      rows = described_class.new(days: 30).call

      expect(rows.map(&:ingredient)).to eq([sugar])
      expect(rows.sole.days_since_used).to eq(60)
    end
  end

  describe Inventory::Reports::TurnoverService do
    it "divides value used by average stock value" do
      move(100, "vendor_invoice", 100, at: Time.zone.local(2026, 9, 1))
      move(-40, "consumption", 100, at: Time.zone.local(2026, 10, 10))
      move(-10, "clear_all_stock", 100, at: Time.zone.local(2026, 10, 20))
      # a transfer is not use company-wide
      move(-5, "transfer_out", 100, at: Time.zone.local(2026, 10, 21))

      result = described_class.new(start_date: start_date, end_date: end_date).call
      row = result.rows.sole

      expect(row.used_qty).to eq(50)
      expect(row.used_value).to eq(5000)
      # average stock (100 + 45) / 2 = 72.5 units x 100
      expect(row.turnover).to eq((5000 / 7250.0).round(2))
      expect(result.days_of_stock).to eq((31 / result.turnover).round(1))
    end

    it "counts transfers out as use when one location is selected" do
      move(100, "vendor_invoice", 100, at: Time.zone.local(2026, 9, 1))
      move(-30, "transfer_out", 100, at: Time.zone.local(2026, 10, 21))

      row = described_class.new(start_date: start_date, end_date: end_date, location: kitchen).call.rows.sole
      expect(row.used_qty).to eq(30)
    end
  end
end
