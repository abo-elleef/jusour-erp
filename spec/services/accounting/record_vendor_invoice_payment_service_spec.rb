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

  # A supplier payment's entry belongs to record_vendor_invoice_payment!, which
  # posts the whole double entry on its own. The Expense it also writes exists so
  # the payment shows up as one — it must post nothing, or cash is credited twice
  # and goods already expensed to Purchases (5100) at receipt are charged again.
  describe "what the ledger ends up holding" do
    before do
      ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: Current.company) do |c|
        c.category_type = "other"
        c.system_managed = true
        c.position = 0
      end
    end

    def pay!(amount_cents)
      described_class.new(vendor_invoice: invoice, user: user, treasury: treasury,
                          amount_cents: amount_cents, payment_date: Date.current).call
    end

    it "credits cash exactly once, for exactly what left the treasury" do
      pay!(5_000)

      cash_moved = JournalEntryLine.joins(:journal_entry)
        .where(journal_entries: { company_id: Current.company.id })
        .where(treasury_id: treasury.id)
        .sum("debit_cents - credit_cents")

      expect(cash_moved).to eq(-5_000)
      expect(treasury.reload.balance_cents).to eq(95_000)
    end

    it "charges no expense account — the goods were expensed when the invoice arrived" do
      pay!(5_000)

      expense_charges = JournalEntryLine.joins(:journal_entry)
        .where(journal_entries: { company_id: Current.company.id })
        .where(account_type: "expense")
        .sum("debit_cents - credit_cents")

      expect(expense_charges).to eq(0)
    end

    it "raises no voucher, since the payment is already its own document" do
      expect { pay!(5_000) }.not_to change(Voucher, :count)
    end

    it "leaves nothing on the accrued-expenses account" do
      pay!(5_000)

      accrued = JournalEntryLine.joins(:journal_entry)
        .where(journal_entries: { company_id: Current.company.id })
        .where(account_code: ::Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE)
        .sum("credit_cents - debit_cents")

      expect(accrued).to eq(0)
    end

    it "still moves the cash out of the treasury" do
      pay!(5_000)

      txn = TreasuryTransaction.find_by(source_record: Expense.last)
      expect(txn.amount_cents).to eq(-5_000)
      expect(txn.treasury_id).to eq(treasury.id)
    end
  end
end
