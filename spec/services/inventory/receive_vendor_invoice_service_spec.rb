# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ReceiveVendorInvoiceService do
  let(:user) { create(:user) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: Current.company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
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
      invoice_number: "INV-1001",
      invoice_date: Date.current,
      received_on: Date.current,
      company: Current.company
    )
    lines.each do |attrs|
      invoice.vendor_invoice_lines.build(
        ingredient: ingredient,
        quantity: attrs.fetch(:quantity),
        unit_price_cents: attrs.fetch(:unit_price_cents, 250)
      )
    end
    invoice
  end

  it "receives stock, records adjustments, and updates price history" do
    invoice = build_invoice(lines: [{ quantity: 4, unit_price_cents: 250 }])

    described_class.new(invoice, user).call

    expect(invoice.reload.total_cents).to eq(1_000)
    expect(ingredient.reload.quantity_on_hand).to eq(14)

    batch = invoice.vendor_invoice_lines.first.stock_batch
    expect(batch).to have_attributes(
      quantity_received: 4,
      quantity_remaining: 4,
      cost_per_unit_cents: 250,
      supplier: supplier
    )

    adjustment = StockAdjustment.find_by(stock_batch: batch)
    expect(adjustment).to have_attributes(
      adjustment_type: "vendor_invoice",
      quantity_delta: 4,
      user: user
    )

    history = SupplierPriceHistory.find_by(supplier: supplier, ingredient: ingredient)
    expect(history.price_cents).to eq(250)
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
end
