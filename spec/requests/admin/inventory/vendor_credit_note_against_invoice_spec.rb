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
    post admin_accounting_vouchers_path, params: {
      voucher: { direction: Voucher::PAYMENT, treasury_id: treasury.id, amount_pounds: "90.00",
                 voucher_date: Date.current.to_s },
      settles: "VendorInvoice:#{invoice.id}"
    }

    invoice.reload
    expect(invoice).to be_paid
    expect(invoice.balance_due_cents).to eq(0)
    expect(ap_treasury.reload.balance_cents).to eq(0)
  end

  it "refuses a payment larger than the balance left after the credit" do
    credit_note = credit_note_for(invoice, quantity: 1, line_total: "10.00")
    post confirm_admin_inventory_vendor_credit_note_path(credit_note)

    expect {
      post admin_accounting_vouchers_path, params: {
        voucher: { direction: Voucher::PAYMENT, treasury_id: treasury.id, amount_pounds: "100.00",
                   voucher_date: Date.current.to_s },
        settles: "VendorInvoice:#{invoice.id}"
      }
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

  describe "voiding a confirmed credit note" do
    let(:ap_treasury) { supplier.reload.ap_treasury }

    def location_on_hand
      IngredientLocation.find_by(ingredient: ingredient, location: location).quantity_on_hand
    end

    it "puts the invoice balance, AP balance, journal and stock back as they were" do
      invoice
      credit_note = credit_note_for(invoice, quantity: 2, line_total: "20.00")
      post confirm_admin_inventory_vendor_credit_note_path(credit_note)
      expect(invoice.reload.balance_due_cents).to eq(8_000)
      expect(ap_treasury.balance_cents).to eq(8_000)
      expect(location_on_hand).to eq(8)
      return_cost = credit_note.stock_adjustments.removals.sole.unit_cost_cents

      patch void_admin_inventory_vendor_credit_note_path(credit_note)

      credit_note.reload
      expect(credit_note).to be_void
      expect(credit_note.voided_by).to eq(owner)
      invoice.reload
      expect(invoice.credit_applied_cents).to eq(0)
      expect(invoice.balance_due_cents).to eq(10_000)
      expect(invoice).to be_unpaid
      expect(invoice).to be_editable
      expect(ap_treasury.reload.balance_cents).to eq(10_000)
      expect(TreasuryTransaction.where(source_record: credit_note)).to be_empty
      expect(JournalEntry.where(source_record_type: "VendorCreditNote", source_record_id: credit_note.id)).to be_empty
      expect(location_on_hand).to eq(10)
      expect(credit_note.stock_adjustments.additions.sole.unit_cost_cents).to eq(return_cost)
      expect(ingredient.stock_batches.where(location: location).sum(:quantity_remaining)).to eq(10)
    end

    it "keeps the invoice locked while another confirmed note is still applied" do
      first = credit_note_for(invoice, quantity: 1, line_total: "10.00")
      post confirm_admin_inventory_vendor_credit_note_path(first)
      second = credit_note_for(invoice, quantity: 1, line_total: "10.00")
      post confirm_admin_inventory_vendor_credit_note_path(second)

      patch void_admin_inventory_vendor_credit_note_path(first)

      invoice.reload
      expect(invoice.credit_applied_cents).to eq(1_000)
      expect(invoice).not_to be_editable
      expect(ap_treasury.reload.balance_cents).to eq(9_000)
    end

    it "voids a price adjustment without touching stock" do
      invoice
      note = VendorCreditNote.create!(
        supplier: supplier, user: owner, company: company, credit_note_date: Date.current,
        kind: "price_adjustment", vendor_invoice: invoice,
        vendor_credit_note_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, quantity: 1, line_total_pounds: "15.00", position: "0" }
        }
      )
      post confirm_admin_inventory_vendor_credit_note_path(note)

      expect { patch void_admin_inventory_vendor_credit_note_path(note) }
        .not_to change(StockAdjustment, :count)

      expect(note.reload).to be_void
      expect(invoice.reload.balance_due_cents).to eq(10_000)
      expect(ap_treasury.reload.balance_cents).to eq(10_000)
    end

    it "refuses a goods return whose stock movements are not linked, changing nothing" do
      credit_note = credit_note_for(invoice, quantity: 1, line_total: "10.00")
      post confirm_admin_inventory_vendor_credit_note_path(credit_note)
      credit_note.stock_adjustments.update_all(vendor_credit_note_id: nil)

      patch void_admin_inventory_vendor_credit_note_path(credit_note)

      expect(flash[:alert]).to eq(I18n.t("inventory.vendor_credit_notes.errors.stock_unlinked"))
      expect(credit_note.reload).to be_confirmed
      expect(invoice.reload.credit_applied_cents).to eq(1_000)
      expect(ap_treasury.reload.balance_cents).to eq(9_000)
    end

    it "is owner-only" do
      credit_note = credit_note_for(invoice, quantity: 1, line_total: "10.00")
      post confirm_admin_inventory_vendor_credit_note_path(credit_note)
      sign_in create(:user, :manager, company: company)

      patch void_admin_inventory_vendor_credit_note_path(credit_note)

      expect(credit_note.reload).to be_confirmed
      expect(ap_treasury.reload.balance_cents).to eq(9_000)
    end
  end
end
