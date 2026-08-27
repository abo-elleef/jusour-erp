# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Landed cost", type: :model do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Importer", lead_time_days: 5, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:product_a) { create(:ingredient, company: company, ingredient_category: category, name: "Drill A", unit: "kg") }
  let(:product_b) { create(:ingredient, company: company, ingredient_category: category, name: "Drill B", unit: "kg") }
  let(:shipment) { ImportShipment.create!(company: company, user: user, location: location, arrival_date: Date.current) }

  before { Current.company = company }

  def batch_for(ingredient, qty:, cost_cents:)
    vi = VendorInvoice.create!(company: company, supplier: supplier, user: user, location: location,
      invoice_number: "VI-#{SecureRandom.hex(3)}", invoice_date: Date.current, received_on: Date.current,
      import_shipment: shipment)
    line = vi.vendor_invoice_lines.create!(ingredient: ingredient, quantity: qty, unit: ingredient.unit,
      line_total_cents: qty * cost_cents)
    StockBatch.create!(ingredient: ingredient, location: location, vendor_invoice_line: line,
      quantity_received: qty, quantity_remaining: qty, cost_per_unit_cents: cost_cents, received_on: Date.current)
  end

  def add_cost(cents)
    ShipmentCost.create!(import_shipment: shipment, user: user, cost_type: "customs",
      amount_cents: cents, incurred_on: Date.current)
  end

  describe Inventory::AllocateLandedCostService do
    it "allocates the pool by value and sets each product's landed unit cost" do
      a = batch_for(product_a, qty: 10, cost_cents: 10_000) # value 100,000
      b = batch_for(product_b, qty: 10, cost_cents: 30_000) # value 300,000
      add_cost(80_000) # pool 80,000 → A 20,000 / B 60,000

      described_class.new(shipment).finalize!

      expect(a.reload.cost_per_unit_cents).to eq(12_000) # 10,000 + 20,000/10
      expect(b.reload.cost_per_unit_cents).to eq(36_000) # 30,000 + 60,000/10
      expect(shipment.reload).to be_finalized
    end

    it "is re-runnable from the provisional baseline when more costs arrive" do
      a = batch_for(product_a, qty: 10, cost_cents: 10_000)
      b = batch_for(product_b, qty: 10, cost_cents: 30_000)
      add_cost(80_000)
      described_class.new(shipment).finalize!

      add_cost(40_000) # pool now 120,000 → recompute from baseline, not compounded
      described_class.new(shipment).finalize!

      expect(a.reload.cost_per_unit_cents).to eq(13_000) # 10,000 + 30,000/10
      expect(b.reload.cost_per_unit_cents).to eq(39_000) # 30,000 + 90,000/10
      expect(a.provisional_cost_per_unit_cents).to eq(10_000) # baseline preserved
    end

    it "honors a manual override and splits the rest by value" do
      a = batch_for(product_a, qty: 10, cost_cents: 10_000)
      b = batch_for(product_b, qty: 10, cost_cents: 30_000)
      add_cost(80_000)

      described_class.new(shipment, overrides: { a.id => 50_000 }).finalize!

      expect(a.reload.cost_per_unit_cents).to eq(15_000) # 10,000 + 50,000/10 (override)
      expect(b.reload.cost_per_unit_cents).to eq(33_000) # 10,000... 30,000 + 30,000/10 (remaining pool)
    end

    it "preview does not persist" do
      a = batch_for(product_a, qty: 10, cost_cents: 10_000)
      batch_for(product_b, qty: 10, cost_cents: 30_000)
      add_cost(80_000)

      rows = described_class.new(shipment).preview
      expect(rows.sum(&:allocated_cents)).to eq(80_000)
      expect(a.reload.cost_per_unit_cents).to eq(10_000) # unchanged
      expect(shipment.reload).to be_open
    end
  end

  describe Inventory::RecordShipmentCostService do
    let(:treasury) do
      Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 500_000,
        opening_balance_cents: 500_000, company: company)
    end

    it "records the cost as a cash-out expense that hits the treasury and joins the pool" do
      cost = described_class.new(shipment: shipment, user: user, cost_type: "customs",
        amount_cents: 25_000, treasury: treasury).call

      expect(cost.expense).to be_present
      expect(treasury.reload.balance_cents).to eq(475_000) # 500,000 - 25,000
      expect(shipment.total_costs_cents).to eq(25_000)
    end

    it "reverses the expense (restores cash) when the cost line is removed" do
      cost = described_class.new(shipment: shipment, user: user, cost_type: "freight",
        amount_cents: 25_000, treasury: treasury).call
      cost.destroy

      expect(treasury.reload.balance_cents).to eq(500_000)
    end
  end
end
