# frozen_string_literal: true

require "rails_helper"

# Phase 3's enabling change: a voucher's far side is resolved per allocation,
# not per voucher. Settling an expense clears the accrued payable; settling a
# supplier invoice clears that supplier's payable, which is a treasury of its
# own. One voucher can do both at once.
RSpec.describe "A voucher settling invoices" do
  let(:company)  { Current.company }
  let(:user)     { create(:user) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg")
  end
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 100_000,
                     opening_balance_cents: 100_000, company: company)
  end

  def balanced?(entry)
    entry.lines.sum(&:debit_cents) == entry.lines.sum(&:credit_cents)
  end

  def entry_for(voucher)
    JournalEntry.for_source(voucher).sole
  end

  describe "a supplier invoice" do
    let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
    let(:invoice) do
      inv = VendorInvoice.new(supplier: supplier, user: user, location: location,
                              invoice_number: "INV-500", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 40_000)
      inv.save!
      # Receiving is what raises the payable; without it there is no balance to settle.
      Accounting::SupplierApLedgerService.record_invoice!(invoice: inv, user: user)
      inv.reload
    end

    def pay!(amount_cents)
      Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: amount_cents,
        allocations: [{ settles: invoice, amount_cents: amount_cents }]
      ).call
    end

    it "clears the supplier's payable rather than the accrual account" do
      voucher = pay!(40_000)

      entry = entry_for(voucher)
      expect(balanced?(entry)).to be(true)
      debit = entry.lines.find { |l| l.debit_cents.positive? }
      expect(debit.treasury_id).to eq(supplier.ap_treasury.id)
      expect(entry.lines.map(&:account_code))
        .not_to include(Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE)
    end

    it "draws down the supplier's balance and the cash together" do
      pay!(40_000)

      expect(cash.reload.balance_cents).to eq(60_000)
      expect(supplier.ap_treasury.reload.balance_cents).to eq(0)
    end

    it "marks the invoice paid" do
      pay!(40_000)

      expect(invoice.reload.amount_paid_cents).to eq(40_000)
      expect(invoice.payment_status).to eq("paid")
      expect(invoice.balance_due_cents).to eq(0)
    end

    it "handles a part payment" do
      pay!(15_000)

      expect(invoice.reload.balance_due_cents).to eq(25_000)
      expect(invoice.payment_status).to eq("partially_paid")
      expect(supplier.ap_treasury.reload.balance_cents).to eq(25_000)
    end
  end

  describe "a customer invoice" do
    let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

    before do
      StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 1000,
                         quantity_remaining: 1000, cost_per_unit_cents: 1_000,
                         received_on: Date.current)
    end

    let(:invoice) do
      inv = CustomerInvoice.new(company: company, customer: customer, user: user,
                                location: location, invoice_date: Date.current)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
                                       unit: ingredient.unit, unit_price_cents: 70_000)
      inv.save!
      Sales::ConfirmCustomerInvoiceService.new(inv, user).call
      inv.reload
    end

    it "clears the customer's receivable and banks the cash" do
      invoice
      voucher = Accounting::RecordVoucherService.new(
        direction: Voucher::RECEIPT, treasury: cash, user: user, amount_cents: 70_000,
        allocations: [{ settles: invoice, amount_cents: 70_000 }]
      ).call

      entry = entry_for(voucher)
      expect(balanced?(entry)).to be(true)
      credit = entry.lines.find { |l| l.credit_cents.positive? }
      expect(credit.treasury_id).to eq(customer.ar_treasury.id)

      expect(cash.reload.balance_cents).to eq(170_000)
      expect(customer.reload.ar_balance_cents).to eq(0)
      expect(invoice.reload.payment_status).to eq("paid")
    end
  end

  describe "one voucher settling several things at once" do
    let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
    let(:invoice) do
      inv = VendorInvoice.new(supplier: supplier, user: user, location: location,
                              invoice_number: "INV-600", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 40_000)
      inv.save!
      # Receiving is what raises the payable; without it there is no balance to settle.
      Accounting::SupplierApLedgerService.record_invoice!(invoice: inv, user: user)
      inv.reload
    end
    let(:expense_category) do
      ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
    end
    let(:expense) do
      Expense.create!(expense_category: expense_category, user: user, company: company,
                      description: "Rent on account", amount_cents: 10_000,
                      expense_date: Date.current)
    end

    it "sends each part to the account that belongs to it" do
      voucher = Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 50_000,
        allocations: [
          { settles: invoice, amount_cents: 40_000 },
          { settles: expense, amount_cents: 10_000 }
        ]
      ).call

      entry = entry_for(voucher)
      expect(balanced?(entry)).to be(true)

      by_code = entry.lines.group_by(&:account_code)
      accrued = by_code[Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE].sole
      ap      = entry.lines.find { |l| l.treasury_id == supplier.ap_treasury.id }

      expect(accrued.debit_cents).to eq(10_000)
      expect(ap.debit_cents).to eq(40_000)
      expect(cash.reload.balance_cents).to eq(50_000)
      expect(invoice.reload.payment_status).to eq("paid")
      expect(expense.reload.outstanding_cents).to eq(0)
    end

    it "sends an unallocated remainder to the accrual account" do
      voucher = Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: user, amount_cents: 50_000,
        allocations: [{ settles: invoice, amount_cents: 40_000 }]
      ).call

      entry = entry_for(voucher)
      expect(balanced?(entry)).to be(true)
      accrued = entry.lines.find do |l|
        l.account_code == Accounting::JournalEntryService::ACCRUED_EXPENSES_CODE
      end
      expect(accrued.debit_cents).to eq(10_000)
      expect(voucher.unallocated_cents).to eq(10_000)
    end
  end
end
