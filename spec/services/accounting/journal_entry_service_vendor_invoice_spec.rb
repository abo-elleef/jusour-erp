# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::JournalEntryService, ".record_vendor_invoice!" do
  let(:user)     { create(:user) }
  let(:location) { create(:location) }
  let(:supplier) { Supplier.create!(name: "Acme Supplies", lead_time_days: 1, company: Current.company) }
  let(:category) do
    IngredientCategory.create!(name: "Dry Goods", position: 1, company: Current.company)
  end
  let(:ingredient) do
    Ingredient.create!(
      name: "Salt", ingredient_category: category,
      unit: "kg", reorder_threshold: 0,
      cost_per_unit_cents: 100, quantity_on_hand: 0,
      company: Current.company
    )
  end

  def build_invoice(invoice_number: "VI-2025-TEST")
    invoice = VendorInvoice.new(
      supplier: supplier, user: user, location: location,
      invoice_number: invoice_number,
      invoice_date: Date.current, received_on: Date.current,
      company: Current.company
    )
    invoice.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 1_000)
    Inventory::ReceiveVendorInvoiceService.new(invoice, user).call
    invoice
  end

  it "creates a journal entry describing the invoice by invoice_number" do
    invoice = build_invoice(invoice_number: "VI-2025-0042")
    je = JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id).last

    expect(je).not_to be_nil
    expect(je.description).to include("VI-2025-0042")
  end

  it "creates balanced debit/credit lines" do
    invoice = build_invoice
    je = JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id).last

    expect(je.total_debits_cents).to eq(je.total_credits_cents)
    expect(je.total_debits_cents).to eq(1_000)
  end

  it "debits the purchases account and credits the AP treasury" do
    invoice = build_invoice
    je = JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id).last

    debit_line  = je.lines.find { |l| l.debit_cents.positive? }
    credit_line = je.lines.find { |l| l.credit_cents.positive? }

    expect(debit_line.account_code).to eq(5100)     # purchases/COGS
    expect(credit_line.account_type).to eq("liability")
    expect(credit_line.treasury_id).to eq(supplier.reload.ap_treasury&.id)
  end

  it "replaces the existing JE when the invoice is re-recorded (idempotent)" do
    invoice = build_invoice
    je_first = JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id).last

    Accounting::JournalEntryService.record_vendor_invoice!(invoice)

    je_ids = JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id).pluck(:id)
    expect(je_ids).not_to include(je_first.id)
    expect(je_ids.count).to eq(1)
  end
end
