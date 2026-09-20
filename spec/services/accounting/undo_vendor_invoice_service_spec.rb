# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::UndoVendorInvoiceService do
  let(:user) { create(:user) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:location) { create(:location, company: Current.company) }
  let(:payment_treasury) do
    Treasury.create!(
      name: "Main Safe",
      treasury_type: "safe",
      opening_balance_cents: 100_000,
      balance_cents: 100_000,
      company: Current.company
    )
  end
  let(:ingredient) do
    Ingredient.create!(
      name: "Tomatoes",
      ingredient_category: IngredientCategory.create!(name: "Produce", position: 1, company: Current.company),
      unit: "kg",
      reorder_threshold: 5,
      cost_per_unit_cents: 200,
      quantity_on_hand: 0,
      company: Current.company
    )
  end

  def receive_invoice!(total_cents: 5_000)
    invoice = VendorInvoice.new(
      supplier: supplier,
      user: user,
      location: location,
      invoice_number: "INV-UNDO-1",
      invoice_date: Date.current,
      received_on: Date.current,
      company: Current.company
    )
    invoice.vendor_invoice_lines.build(
      ingredient: ingredient,
      quantity: 10,
      line_total_cents: total_cents
    )
    Inventory::ReceiveVendorInvoiceService.new(invoice, user).call
    invoice
  end

  def record_payment!(invoice, amount_cents:, treasury: payment_treasury)
    Accounting::RecordVendorInvoicePaymentService.new(
      vendor_invoice: invoice,
      user: user,
      treasury: treasury,
      amount_cents: amount_cents,
      payment_date: Date.current
    ).call
  end

  describe "unpaid invoice" do
    it "voids the invoice and restores the supplier AP balance" do
      invoice = receive_invoice!(total_cents: 5_000)
      ap = supplier.reload.ap_treasury
      expect(ap.balance_cents).to eq(5_000)

      described_class.new(invoice: invoice, user: user).call

      invoice.reload
      ap.reload

      expect(invoice).to be_void
      expect(invoice.amount_paid_cents).to eq(0)
      expect(ap.balance_cents).to eq(0)
      expect(TreasuryTransaction.where(source_record: invoice)).to be_empty
      expect(JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id)).to be_empty
    end
  end

  describe "fully paid invoice" do
    it "restores both the payment treasury and the supplier AP balance" do
      invoice = receive_invoice!(total_cents: 5_000)
      ap = supplier.reload.ap_treasury
      expect(ap.balance_cents).to eq(5_000)

      voucher = record_payment!(invoice, amount_cents: 5_000)

      invoice.reload
      payment_treasury.reload
      ap.reload

      expect(invoice).to be_paid
      expect(payment_treasury.balance_cents).to eq(95_000)
      expect(ap.balance_cents).to eq(0)

      described_class.new(invoice: invoice, user: user).call

      invoice.reload
      payment_treasury.reload
      ap.reload

      expect(invoice).to be_void
      expect(invoice.amount_paid_cents).to eq(0)
      expect(invoice.payment_vouchers).to be_empty
      expect(voucher.reload).to be_voided
      expect(payment_treasury.balance_cents).to eq(100_000)
      expect(ap.balance_cents).to eq(0)
      expect(TreasuryTransaction.where(source_record: invoice)).to be_empty
      expect(TreasuryTransaction.where(source_record_type: "Voucher")).to be_empty
      expect(JournalEntry.where(source_record_type: "VendorInvoice", source_record_id: invoice.id)).to be_empty
      expect(JournalEntry.where(source_record_type: "Voucher")).to be_empty
    end
  end

  describe "partially paid invoice with multiple treasuries" do
    let(:second_treasury) do
      Treasury.create!(
        name: "Bank Account",
        treasury_type: "bank",
        opening_balance_cents: 50_000,
        balance_cents: 50_000,
        company: Current.company
      )
    end

    it "restores each payment treasury and leaves AP at zero" do
      invoice = receive_invoice!(total_cents: 5_000)
      ap = supplier.reload.ap_treasury

      record_payment!(invoice, amount_cents: 2_000, treasury: payment_treasury)
      record_payment!(invoice, amount_cents: 3_000, treasury: second_treasury)

      payment_treasury.reload
      second_treasury.reload
      ap.reload

      expect(payment_treasury.balance_cents).to eq(98_000)
      expect(second_treasury.balance_cents).to eq(47_000)
      expect(ap.balance_cents).to eq(0)

      described_class.new(invoice: invoice.reload, user: user).call

      payment_treasury.reload
      second_treasury.reload
      ap.reload
      invoice.reload

      expect(invoice).to be_void
      expect(payment_treasury.balance_cents).to eq(100_000)
      expect(second_treasury.balance_cents).to eq(50_000)
      expect(ap.balance_cents).to eq(0)
      expect(Expense.where("description LIKE ?", "%INV-UNDO-1%")).to be_empty
    end
  end

  it "raises when the invoice is already void" do
    invoice = receive_invoice!(total_cents: 1_000)
    invoice.update!(payment_status: "void")

    expect do
      described_class.new(invoice: invoice, user: user).call
    end.to raise_error(Accounting::UndoVendorInvoiceService::Error)
  end
end
