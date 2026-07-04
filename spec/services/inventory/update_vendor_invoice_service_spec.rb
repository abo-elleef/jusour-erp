# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::UpdateVendorInvoiceService do
  let(:user) { create(:user) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: Current.company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:location) { create(:location, company: Current.company, name: "Branch A") }
  let(:other_location) { create(:location, company: Current.company, name: "Branch B") }
  let(:ingredient) do
    Ingredient.create!(
      name: "Tomatoes",
      ingredient_category: category,
      unit: "kg",
      reorder_threshold: 5,
      cost_per_unit_cents: 200,
      quantity_on_hand: 0,
      company: Current.company
    )
  end

  def receive_invoice!(quantity: 4)
    invoice = VendorInvoice.new(
      supplier: supplier,
      user: user,
      location: location,
      invoice_number: "INV-EDIT-1",
      invoice_date: Date.current,
      received_on: Date.current,
      company: Current.company
    )
    invoice.vendor_invoice_lines.build(ingredient: ingredient, quantity: quantity, line_total_cents: quantity * 250)
    Inventory::ReceiveVendorInvoiceService.new(invoice, user).call
    invoice
  end

  it "updates invoice details and adjusts stock at the location" do
    invoice = receive_invoice!(quantity: 4)
    line = invoice.vendor_invoice_lines.first

    described_class.new(
      invoice,
      user,
      {
        supplier_id: supplier.id,
        location_id: other_location.id,
        invoice_number: "INV-EDIT-1-REV",
        invoice_date: invoice.invoice_date,
        received_on: invoice.received_on,
        notes: "Updated",
        vendor_invoice_lines_attributes: {
          "0" => {
            id: line.id,
            ingredient_id: ingredient.id,
            quantity: "6",
            line_total_cents: 1_800
          }
        }
      }
    ).call

    invoice.reload
    expect(invoice.invoice_number).to eq("INV-EDIT-1-REV")
    expect(invoice.location).to eq(other_location)
    expect(invoice.total_cents).to eq(1_800)
    expect(ingredient.reload.quantity_on_hand.to_f).to eq(6.0)

    il = IngredientLocation.find_by(location: other_location, ingredient: ingredient)
    expect(il.quantity_on_hand.to_f).to eq(6.0)

    old_il = IngredientLocation.find_by(location: location, ingredient: ingredient)
    expect(old_il&.quantity_on_hand.to_f).to eq(0.0)
  end

  it "raises when stock from the invoice has been consumed" do
    invoice = receive_invoice!(quantity: 4)
    line = invoice.vendor_invoice_lines.first
    line.stock_batch.update!(quantity_remaining: 1)

    expect do
      described_class.new(
        invoice,
        user,
        {
          supplier_id: supplier.id,
          location_id: location.id,
          invoice_number: invoice.invoice_number,
          invoice_date: invoice.invoice_date,
          received_on: invoice.received_on,
          vendor_invoice_lines_attributes: {
            "0" => {
              id: line.id,
              ingredient_id: ingredient.id,
              quantity: "3",
              line_total_cents: 750
            }
          }
        }
      ).call
    end.to raise_error(Inventory::UpdateVendorInvoiceService::Error)
  end
end
