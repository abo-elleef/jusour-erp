# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Receiving a vendor invoice in an alternate unit", type: :model do
  let(:user) { create(:user) }
  let(:supplier) { Supplier.create!(name: "Oil Co", company: Current.company) }
  let(:location) { create(:location, company: Current.company, name: "Central Kitchen") }
  let(:category) { IngredientCategory.create!(name: "Oils", position: 1, company: Current.company) }
  let(:oil) do
    ing = Ingredient.create!(name: "Sunflower Oil", ingredient_category: category, unit: "ml",
      reorder_threshold: 100, cost_per_unit_cents: 0, quantity_on_hand: 0, company: Current.company)
    ing.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, company: Current.company)
    ing
  end

  def receive!(quantity:, unit:, line_total_cents:)
    invoice = VendorInvoice.new(
      supplier: supplier, user: user, location: location, invoice_number: "VI-OIL-#{rand(9999)}",
      invoice_date: Date.current, received_on: Date.current, company: Current.company
    )
    invoice.vendor_invoice_lines.build(ingredient: oil, quantity: quantity, unit: unit, line_total_cents: line_total_cents)
    Inventory::ReceiveVendorInvoiceService.new(invoice, user).call
    invoice
  end

  it "converts the purchase unit to the base unit and costs per base unit" do
    # 2 gallons @ 7,570.00 total → 7,570 ml, cost 100 cents/ml
    invoice = receive!(quantity: 2, unit: "gallons", line_total_cents: 757_000)
    batch = invoice.vendor_invoice_lines.first.stock_batch

    expect(batch.quantity_received.to_d).to eq(7_570)
    expect(batch.quantity_remaining.to_d).to eq(7_570)
    expect(batch.cost_per_unit_cents).to eq(100) # per ml
    expect(oil.reload.quantity_on_hand.to_d).to eq(7_570)

    il = IngredientLocation.find_by(location: location, ingredient: oil)
    expect(il.quantity_on_hand.to_d).to eq(7_570)
  end

  it "keeps the invoice total exact even when per-unit cost rounds" do
    # 1 gallon @ 5,500.00 → 3,785 ml; per-ml cost rounds but the line total is the truth.
    invoice = receive!(quantity: 1, unit: "gallons", line_total_cents: 550_000)
    line = invoice.vendor_invoice_lines.first

    expect(line.base_quantity).to eq(3_785)
    expect(line.line_total_cents).to eq(550_000)          # exact
    expect(line.stock_batch.cost_per_unit_cents).to eq(145) # 550000 / 3785 ≈ 145.3, rounded
  end

  it "records supplier price history per base unit" do
    receive!(quantity: 2, unit: "gallons", line_total_cents: 757_000)
    history = SupplierPriceHistory.find_by(supplier: supplier, ingredient: oil)
    expect(history.price_cents).to eq(100) # per ml, not per gallon
  end
end
