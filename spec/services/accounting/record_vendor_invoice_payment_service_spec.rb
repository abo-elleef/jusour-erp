# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::RecordVendorInvoicePaymentService do
  let(:user) { create(:user) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: Current.company) }
  let(:location) { create(:location, company: Current.company) }
  let(:treasury) do
    Treasury.create!(
      name: "Main Safe",
      treasury_type: "safe",
      opening_balance_cents: 100_000,
      balance_cents: 100_000,
      company: Current.company
    )
  end
  let(:invoice) do
    invoice = VendorInvoice.new(
      supplier: supplier,
      user: user,
      location: location,
      invoice_number: "INV-2001",
      invoice_date: Date.current,
      received_on: Date.current,
      company: Current.company
    )
    invoice.vendor_invoice_lines.build(
      ingredient: Ingredient.create!(
        name: "Tomatoes",
        ingredient_category: IngredientCategory.create!(name: "Produce", position: 1, company: Current.company),
        unit: "kg",
        reorder_threshold: 5,
        cost_per_unit_cents: 200,
        quantity_on_hand: 0,
        company: Current.company
      ),
      quantity: 10,
      line_total_cents: 5_000
    )
    invoice.save!
    invoice
  end

  it "records a full payment and marks the invoice paid" do
    payment = described_class.new(
      vendor_invoice: invoice,
      user: user,
      treasury: treasury,
      amount_cents: 5_000,
      payment_date: Date.current
    ).call

    invoice.reload
    treasury.reload

    expect(invoice).to be_paid
    expect(invoice.amount_paid_cents).to eq(5_000)
    expect(invoice.balance_due_cents).to eq(0)
    expect(payment.expense).to have_attributes(
      amount_cents: 5_000,
      is_auto_generated: true,
      treasury: treasury
    )
    expect(payment.expense.expense_category.name).to eq("Vendor purchases")
    expect(treasury.balance_cents).to eq(95_000)
  end

  it "supports multiple partial payments until fully paid" do
    described_class.new(
      vendor_invoice: invoice,
      user: user,
      treasury: treasury,
      amount_cents: 2_000,
      payment_date: Date.current
    ).call

    invoice.reload
    treasury.reload

    expect(invoice).to be_partially_paid
    expect(invoice.amount_paid_cents).to eq(2_000)
    expect(invoice.balance_due_cents).to eq(3_000)
    expect(treasury.balance_cents).to eq(98_000)
    expect(invoice.vendor_invoice_payments.count).to eq(1)

    described_class.new(
      vendor_invoice: invoice,
      user: user,
      treasury: treasury,
      amount_cents: 3_000,
      payment_date: Date.current
    ).call

    invoice.reload
    treasury.reload

    expect(invoice).to be_paid
    expect(invoice.amount_paid_cents).to eq(5_000)
    expect(invoice.vendor_invoice_payments.count).to eq(2)
    expect(treasury.balance_cents).to eq(95_000)
  end

  it "raises when the invoice is fully paid" do
    invoice.update!(payment_status: "paid", amount_paid_cents: invoice.total_cents)

    expect do
      described_class.new(
        vendor_invoice: invoice,
        user: user,
        treasury: treasury,
        amount_cents: 100
      ).call
    end.to raise_error(Accounting::RecordVendorInvoicePaymentService::Error, "Invoice cannot accept payments")
  end

  it "raises when payment exceeds balance due" do
    expect do
      described_class.new(
        vendor_invoice: invoice,
        user: user,
        treasury: treasury,
        amount_cents: invoice.total_cents + 100
      ).call
    end.to raise_error(Accounting::RecordVendorInvoicePaymentService::Error, "Payment amount exceeds balance due")
  end
end
