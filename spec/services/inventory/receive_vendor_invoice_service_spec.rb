# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ReceiveVendorInvoiceService do
  let(:user) { create(:user) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: Current.company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:location) { create(:location, company: Current.company, name: "Central Kitchen") }
  let(:ingredient) do
    Ingredient.create!(
      name: "Tomatoes",
      ingredient_category: category,
      unit: "kg",
      reorder_threshold: 5,
      cost_per_unit_cents: 200,
      quantity_on_hand: 10,
      company: Current.company
    )
  end

  def build_invoice(lines:)
    invoice = VendorInvoice.new(
      supplier: supplier,
      user: user,
      location: location,
      invoice_number: "INV-1001",
      invoice_date: Date.current,
      received_on: Date.current,
      company: Current.company
    )
    lines.each do |attrs|
      quantity = attrs.fetch(:quantity)
      unit_price_cents = attrs.fetch(:unit_price_cents, 250)
      invoice.vendor_invoice_lines.build(
        ingredient: ingredient,
        quantity: quantity,
        # line_total is the stored source of truth; unit price is derived from it.
        line_total_cents: quantity * unit_price_cents
      )
    end
    invoice
  end

  it "receives stock at the location and updates company total" do
    invoice = build_invoice(lines: [{ quantity: 4, unit_price_cents: 250 }])

    described_class.new(invoice, user).call

    expect(invoice.reload.total_cents).to eq(1_000)
    expect(ingredient.reload.quantity_on_hand.to_f).to eq(14.0)

    il = IngredientLocation.find_by(location: location, ingredient: ingredient)
    expect(il.quantity_on_hand.to_f).to eq(4.0)
    expect(il.reorder_threshold).to eq(ingredient.reorder_threshold)

    batch = invoice.vendor_invoice_lines.first.stock_batch
    expect(batch).to have_attributes(
      quantity_received: 4,
      quantity_remaining: 4,
      cost_per_unit_cents: 250,
      supplier: supplier,
      location: location
    )

    adjustment = StockAdjustment.find_by(stock_batch: batch)
    expect(adjustment).to have_attributes(
      adjustment_type: "vendor_invoice",
      quantity_delta: 4,
      user: user,
      location: location
    )

    history = SupplierPriceHistory.find_by(supplier: supplier, ingredient: ingredient)
    expect(history.price_cents).to eq(250)
  end

  it "adds to existing location stock when ingredient is already assigned" do
    create(:ingredient_location, location: location, ingredient: ingredient, quantity_on_hand: 3.0)

    invoice = build_invoice(lines: [{ quantity: 2, unit_price_cents: 250 }])
    described_class.new(invoice, user).call

    il = IngredientLocation.find_by(location: location, ingredient: ingredient)
    expect(il.quantity_on_hand.to_f).to eq(5.0)
    expect(ingredient.reload.quantity_on_hand.to_f).to eq(12.0)
  end

  it "skips price history when unit price is unchanged" do
    SupplierPriceHistory.create!(
      supplier: supplier,
      ingredient: ingredient,
      price_cents: 250,
      effective_date: 1.week.ago.to_date,
      recorded_by_user: user
    )

    invoice = build_invoice(lines: [{ quantity: 2, unit_price_cents: 250 }])
    expect { described_class.new(invoice, user).call }
      .not_to change(SupplierPriceHistory, :count)
  end

  it "applies a percentage discount to the invoice total" do
    invoice = build_invoice(lines: [{ quantity: 4, unit_price_cents: 250 }])
    invoice.discount_type = "percentage"
    invoice.discount_value = 10
    invoice.discount_notes = "Volume rebate"

    described_class.new(invoice, user).call

    expect(invoice.reload.total_cents).to eq(900)
    expect(invoice.subtotal_cents).to eq(1_000)
    expect(invoice.discount_cents).to eq(100)
    expect(invoice.discount_notes).to eq("Volume rebate")
  end

  it "applies a fixed discount capped at subtotal" do
    invoice = build_invoice(lines: [{ quantity: 4, unit_price_cents: 250 }])
    invoice.discount_type = "fixed_amount"
    invoice.discount_value = 150

    described_class.new(invoice, user).call

    expect(invoice.reload.total_cents).to eq(850)
  end
end
