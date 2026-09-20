# frozen_string_literal: true

require "rails_helper"

# Every accounting page, loaded against a company that has one of everything.
#
# Twice in one week the full suite went green over a page that would have
# returned 500 in production — `payment.payment_date` on a vendor invoice whose
# payments had become vouchers, and `record.description` on the voucher index
# once a voucher could settle an invoice. Both were views reading a polymorphic
# association that had quietly gained a new member, and both were invisible
# because no spec had ever rendered that page with the relevant data on it.
#
# This is the backstop: it proves nothing about correctness, only that no
# accounting page explodes when there is real data behind it. Driven by
# AccountingNav so a new tab is covered the day it is added.
RSpec.describe "Accounting pages, with data behind them", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  # One of everything an accounting page might try to render.
  before do
    sign_in owner
    seed_accounting_data!
  end

  AccountingNav::GROUPS.flat_map { |group| group[:tabs] }.each do |tab|
    name = [tab[:controller], tab[:action]].compact.join("#")

    it "renders #{name}" do
      path = send(tab[:path])

      get path

      # A gated or forbidden tab is a legitimate answer; a 500 never is.
      expect(response.status).to be < 500,
        "#{name} (#{path}) returned #{response.status}"
    end
  end

  describe "the record pages themselves" do
    it "renders an expense, an income and every voucher" do
      get admin_accounting_expense_path(@paid_expense)
      expect(response).to have_http_status(:ok)

      get admin_accounting_income_path(@income)
      expect(response).to have_http_status(:ok)

      Voucher.find_each do |voucher|
        get admin_accounting_voucher_path(voucher)
        expect(response).to have_http_status(:ok), "voucher #{voucher.number} returned #{response.status}"
      end
    end

    it "renders every journal entry the seed produced" do
      expect(JournalEntry.count).to be_positive

      JournalEntry.find_each do |entry|
        get admin_accounting_journal_entry_path(entry)
        expect(response).to have_http_status(:ok), "#{entry.entry_number} returned #{response.status}"
      end
    end

    it "renders the supplier invoice that a voucher paid" do
      get admin_inventory_vendor_invoice_path(@vendor_invoice)
      expect(response).to have_http_status(:ok)
    end
  end

  # ── Fixture ───────────────────────────────────────────────────────────
  #
  # Deliberately built through the real services, so the pages see the records
  # exactly as production writes them rather than a hand-assembled shape.
  def seed_accounting_data!
    location = create(:location, company: company)
    ing_category = create(:ingredient_category, company: company)
    ingredient = create(:ingredient, company: company, ingredient_category: ing_category,
                        name: "Tomatoes", unit: "kg")
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 1000,
                       quantity_remaining: 1000, cost_per_unit_cents: 1_000, received_on: Date.current)

    cash = Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 500_000,
                            opening_balance_cents: 500_000, company: company)
    expense_category = ExpenseCategory.create!(name: "Rent", category_type: "rent",
                                               position: 1, company: company)
    income_category = IncomeCategory.create!(name: "Catering", category_type: "catering",
                                             position: 1, company: company)

    # Paid on issue, and on account — the two halves of the accrual split.
    @paid_expense = Expense.create!(company: company, user: owner, treasury: cash,
                                    expense_category: expense_category, description: "Rent paid",
                                    amount_cents: 20_000, expense_date: Date.current)
    @unpaid_expense = Expense.create!(company: company, user: owner,
                                      expense_category: expense_category, description: "Rent owed",
                                      amount_cents: 30_000, expense_date: Date.current)
    @income = Income.create!(company: company, user: owner, treasury: cash,
                             income_category: income_category, description: "Catering",
                             amount_cents: 15_000, income_date: Date.current)

    # A voucher settling the unpaid expense.
    Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: cash, user: owner, amount_cents: 30_000,
      allocations: [{ settles: @unpaid_expense, amount_cents: 30_000 }]
    ).call

    # A supplier invoice, received and then paid by voucher.
    supplier = Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company)
    @vendor_invoice = VendorInvoice.new(supplier: supplier, user: owner, location: location,
                                        invoice_number: "INV-SMOKE", invoice_date: Date.current,
                                        received_on: Date.current, company: company)
    @vendor_invoice.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10,
                                               line_total_cents: 40_000)
    @vendor_invoice.save!
    Accounting::SupplierApLedgerService.record_invoice!(invoice: @vendor_invoice, user: owner)
    Accounting::RecordVendorInvoicePaymentService.new(
      vendor_invoice: @vendor_invoice.reload, user: owner, treasury: cash,
      amount_cents: 15_000, payment_date: Date.current
    ).call

    # A customer invoice, confirmed and then part-paid — which also leaves the
    # customer in credit, so an on-account allocation gets rendered too.
    customer = create(:customer, company: company, name: "Clinic", customer_type: "commercial")
    invoice = CustomerInvoice.new(company: company, customer: customer, user: owner,
                                  location: location, invoice_date: Date.current)
    invoice.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
                                         unit: ingredient.unit, unit_price_cents: 50_000)
    invoice.save!
    Sales::ConfirmCustomerInvoiceService.new(invoice, owner).call
    Sales::RecordCustomerPaymentService.new(
      customer: customer, treasury: cash, amount_cents: 60_000, user: owner
    ).call
  end
end
