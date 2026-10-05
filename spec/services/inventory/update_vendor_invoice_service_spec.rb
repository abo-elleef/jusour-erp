# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::UpdateVendorInvoiceService do
  include ActiveJob::TestHelper

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

  let(:treasury) do
    Treasury.create!(
      name: "Main Safe",
      treasury_type: "safe",
      opening_balance_cents: 1_000_000,
      balance_cents: 1_000_000,
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

  it "unlinks the old stock batch from the line after edit so subsequent edits work" do
    invoice = receive_invoice!(quantity: 4)
    line = invoice.vendor_invoice_lines.first
    original_batch = line.stock_batch

    # First edit: change quantity from 4 → 6
    described_class.new(
      invoice, user,
      {
        supplier_id: supplier.id, location_id: location.id,
        invoice_number: invoice.invoice_number,
        invoice_date: invoice.invoice_date, received_on: invoice.received_on,
        vendor_invoice_lines_attributes: {
          "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "6", line_total_cents: 1_500 }
        }
      }
    ).call

    line.reload
    new_batch = line.stock_batch

    # Old batch must be unlinked so line.stock_batch returns the new one
    expect(new_batch).not_to eq(original_batch)
    expect(new_batch).not_to be_nil
    expect(original_batch.reload.vendor_invoice_line_id).to be_nil

    # Second edit must succeed (not raise StockConsumedError on the old zero batch)
    expect do
      described_class.new(
        invoice, user,
        {
          supplier_id: supplier.id, location_id: location.id,
          invoice_number: invoice.invoice_number,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          vendor_invoice_lines_attributes: {
            "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "5", line_total_cents: 1_250 }
          }
        }
      ).call
    end.not_to raise_error
  end

  it "still allows editing when stock from the invoice has already been consumed" do
    invoice = receive_invoice!(quantity: 4)
    line = invoice.vendor_invoice_lines.first
    original_batch = line.stock_batch
    original_batch.update!(quantity_remaining: 1)

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

    # The already-consumed portion is reflected as a negative remainder on the
    # old (now unlinked) batch, mirroring how on-hand is already allowed to go
    # negative elsewhere; a fresh batch carries the newly edited quantity.
    expect(original_batch.reload.quantity_remaining.to_f).to eq(-3.0)
    expect(original_batch.vendor_invoice_line_id).to be_nil

    line.reload
    expect(line.quantity.to_f).to eq(3.0)
    expect(line.stock_batch.quantity_remaining.to_f).to eq(3.0)
    expect(ingredient.reload.quantity_on_hand.to_f).to eq(3.0)
  end

  it "allows editing a fully paid invoice and re-syncs payment status when the total rises" do
    invoice = receive_invoice!(quantity: 4) # total 1,000
    Accounting::RecordVendorInvoicePaymentService.new(
      vendor_invoice: invoice, user: user, treasury: treasury, amount_cents: 1_000
    ).call
    expect(invoice.reload).to be_paid

    line = invoice.vendor_invoice_lines.first
    described_class.new(
      invoice, user,
      {
        supplier_id: supplier.id, location_id: location.id,
        invoice_number: invoice.invoice_number,
        invoice_date: invoice.invoice_date, received_on: invoice.received_on,
        vendor_invoice_lines_attributes: {
          "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "6", line_total_cents: 1_800 }
        }
      }
    ).call

    invoice.reload
    expect(invoice.total_cents).to eq(1_800)
    expect(invoice.amount_paid_cents).to eq(1_000)
    expect(invoice).to be_partially_paid
    expect(invoice.balance_due_cents).to eq(800)
  end

  it "leaves a negative balance when editing a paid invoice down, with no extra ledger entry" do
    invoice = receive_invoice!(quantity: 4) # total 1,000
    Accounting::RecordVendorInvoicePaymentService.new(
      vendor_invoice: invoice, user: user, treasury: treasury, amount_cents: 1_000
    ).call
    ap_treasury = supplier.reload.ap_treasury
    expect(ap_treasury.balance_cents).to eq(0)

    line = invoice.vendor_invoice_lines.first
    edit = lambda do
      described_class.new(
        invoice, user,
        {
          supplier_id: supplier.id, location_id: location.id,
          invoice_number: invoice.invoice_number,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          vendor_invoice_lines_attributes: {
            "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "3", line_total_cents: 750 }
          }
        }
      ).call
    end

    expect { edit.call }
      .to have_enqueued_job(Accounting::NotifyVendorBalanceNegativeJob)
      .with(supplier.id, invoice.id, -250)

    invoice.reload
    expect(invoice.total_cents).to eq(750)
    expect(invoice.amount_paid_cents).to eq(1_000)
    expect(invoice.credit_applied_cents).to eq(0)
    expect(invoice).to be_paid
    expect(invoice.balance_due_cents).to eq(-250)

    # The ap_invoice leg moved from +1,000 to +750; the ap_payment leg (-1,000)
    # was never touched — the treasury nets to -250 with no separate entry.
    expect(VendorCreditNote.where(supplier: supplier).count).to eq(0)
    expect(ap_treasury.reload.balance_cents).to eq(-250)
  end

  describe "vendor-balance-negative alert" do
    it "does not alert when the edit leaves the balance at zero or positive" do
      invoice = receive_invoice!(quantity: 4) # total 1,000
      Accounting::RecordVendorInvoicePaymentService.new(
        vendor_invoice: invoice, user: user, treasury: treasury, amount_cents: 1_000
      ).call
      line = invoice.vendor_invoice_lines.first

      # Price goes up: still fully paid, balance due goes positive, not negative.
      expect {
        described_class.new(
          invoice, user,
          {
            supplier_id: supplier.id, location_id: location.id,
            invoice_number: invoice.invoice_number,
            invoice_date: invoice.invoice_date, received_on: invoice.received_on,
            vendor_invoice_lines_attributes: {
              "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "4", line_total_cents: 1_200 }
            }
          }
        ).call
      }.not_to have_enqueued_job(Accounting::NotifyVendorBalanceNegativeJob)
    end

    it "does not re-alert when the balance was already negative before this edit" do
      invoice = receive_invoice!(quantity: 4) # total 1,000
      Accounting::RecordVendorInvoicePaymentService.new(
        vendor_invoice: invoice, user: user, treasury: treasury, amount_cents: 1_000
      ).call
      line = invoice.vendor_invoice_lines.first

      # First edit: crosses zero, -250. Drain the queue before the second edit.
      described_class.new(
        invoice, user,
        {
          supplier_id: supplier.id, location_id: location.id,
          invoice_number: invoice.invoice_number,
          invoice_date: invoice.invoice_date, received_on: invoice.received_on,
          vendor_invoice_lines_attributes: {
            "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "3", line_total_cents: 750 }
          }
        }
      ).call
      clear_enqueued_jobs

      # Second edit: still negative throughout, no fresh crossing to report.
      expect {
        described_class.new(
          invoice, user,
          {
            supplier_id: supplier.id, location_id: location.id,
            invoice_number: invoice.invoice_number,
            invoice_date: invoice.invoice_date, received_on: invoice.received_on,
            vendor_invoice_lines_attributes: {
              "0" => { id: line.id, ingredient_id: ingredient.id, quantity: "2", line_total_cents: 500 }
            }
          }
        ).call
      }.not_to have_enqueued_job(Accounting::NotifyVendorBalanceNegativeJob)
    end
  end
end
