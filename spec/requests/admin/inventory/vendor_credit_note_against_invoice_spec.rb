# frozen_string_literal: true

require "rails_helper"

# The scenario this exists for: a 10,000 invoice, a 1,000 return against it, then
# paying the invoice off. Before credit notes were linked to invoices, the AP
# treasury dropped to 9,000 while the invoice still read 10,000 due — so settling
# the invoice in full drove the supplier's AP balance to -1,000.
RSpec.describe "Vendor credit note applied to an invoice", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let!(:treasury) do
    Treasury.create!(name: "Main Safe", treasury_type: "safe", balance_cents: 5_000_000,
      opening_balance_cents: 5_000_000, is_default: true, company: company)
  end
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 1_000, quantity_on_hand: 0, company: company)
  end

  before { sign_in owner }

  # A posted 10,000 invoice: 10 kg at 1,000 each.
  let(:invoice) do
    inv = VendorInvoice.new(supplier: supplier, location: location, user: owner, company: company,
      invoice_date: Date.current, received_on: Date.current, draft: false,
      vendor_invoice_lines_attributes: {
        "0" => { ingredient_id: ingredient.id, quantity: 10, line_total_cents: 10_000 }
      })
    Inventory::ReceiveVendorInvoiceService.new(inv, owner).call
  end

  def credit_note_for(invoice, quantity:, line_total:)
    VendorCreditNote.create!(
      supplier: supplier, user: owner, company: company, credit_note_date: Date.current,
      kind: "goods_return", location: location, vendor_invoice: invoice,
      vendor_credit_note_lines_attributes: {
        "0" => { ingredient_id: ingredient.id, quantity: quantity, line_total_pounds: line_total, position: "0" }
      }
    )
  end

  it "settles the invoice and leaves the AP balance at zero, not negative" do
    ap_treasury = supplier.reload.ap_treasury
    expect(invoice.total_cents).to eq(10_000)
    expect(ap_treasury.reload.balance_cents).to eq(10_000)

    credit_note = credit_note_for(invoice, quantity: 1, line_total: "10.00")
    post confirm_admin_inventory_vendor_credit_note_path(credit_note)

    invoice.reload
    expect(invoice.credit_applied_cents).to eq(1_000)
    expect(invoice.balance_due_cents).to eq(9_000)
    expect(invoice).to be_partially_paid
    expect(ap_treasury.reload.balance_cents).to eq(9_000)

    # Paying the remaining balance closes the invoice and lands the AP at zero.
    post record_payment_admin_inventory_vendor_invoice_path(invoice),
      params: { treasury_id: treasury.id, payment_amount_dollars: "90.00" }

    invoice.reload
    expect(invoice).to be_paid
    expect(invoice.balance_due_cents).to eq(0)
    expect(ap_treasury.reload.balance_cents).to eq(0)
  end

  it "refuses a payment larger than the balance left after the credit" do
    credit_note = credit_note_for(invoice, quantity: 1, line_total: "10.00")
    post confirm_admin_inventory_vendor_credit_note_path(credit_note)

    expect {
      post record_payment_admin_inventory_vendor_invoice_path(invoice),
        params: { treasury_id: treasury.id, payment_amount_dollars: "100.00" }
    }.not_to change { invoice.reload.amount_paid_cents }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(invoice.balance_due_cents).to eq(9_000)
  end

  it "closes the invoice outright when the whole thing is credited back" do
    credit_note = credit_note_for(invoice, quantity: 10, line_total: "100.00")
    post confirm_admin_inventory_vendor_credit_note_path(credit_note)

    invoice.reload
    expect(invoice).to be_paid
    expect(invoice.balance_due_cents).to eq(0)
    expect(supplier.reload.ap_treasury.balance_cents).to eq(0)
  end

  it "refuses a credit larger than the invoice balance" do
    invoice
    note = VendorCreditNote.new(
      supplier: supplier, user: owner, company: company, credit_note_date: Date.current,
      kind: "goods_return", location: location, vendor_invoice: invoice,
      vendor_credit_note_lines_attributes: {
        "0" => { ingredient_id: ingredient.id, quantity: 11, line_total_pounds: "110.00", position: "0" }
      }
    )
    expect(note).not_to be_valid
    expect(note.errors[:base].join).to include(invoice.invoice_number)
  end

  it "refuses an invoice belonging to a different supplier" do
    other = Supplier.create!(name: "Other Farms", company: company)
    note = VendorCreditNote.new(
      supplier: other, user: owner, company: company, credit_note_date: Date.current,
      kind: "price_adjustment", vendor_invoice: invoice,
      vendor_credit_note_lines_attributes: {
        "0" => { ingredient_id: ingredient.id, quantity: 1, line_total_pounds: "1.00", position: "0" }
      }
    )
    expect(note).not_to be_valid
    expect(note.errors[:vendor_invoice]).to be_present
  end
end
