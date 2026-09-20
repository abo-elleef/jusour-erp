# frozen_string_literal: true

require "rails_helper"

# Finding the document that paid something used to be possible only from the
# voucher's side. And the expense page printed a Ruby object inspect —
# "#<VendorInvoicePayment:0x000077818411e4c8>" — where a source record's name
# belonged, because the view fell back to `record.to_s`.
RSpec.describe "Linking a record to the voucher that settled it", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 200_000,
                     opening_balance_cents: 200_000, company: company)
  end
  let(:category) do
    ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
  end

  before { sign_in owner }

  describe "an expense paid on issue" do
    it "links to the voucher that paid it" do
      expense = Expense.create!(company: company, user: owner, treasury: cash,
                                expense_category: category, description: "Rent",
                                amount_cents: 20_000, expense_date: Date.current)
      voucher = expense.payment_allocations.sole.payment

      get admin_accounting_expense_path(expense)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(voucher.number)
      expect(response.body).to include(admin_accounting_voucher_path(voucher))
    end
  end

  describe "an expense on account" do
    it "says what is still owed, and that nothing has settled it" do
      expense = Expense.create!(company: company, user: owner, expense_category: category,
                                description: "Rent owed", amount_cents: 30_000,
                                expense_date: Date.current)

      get admin_accounting_expense_path(expense)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.vouchers.not_settled_yet"))
    end

    it "links to the voucher once one settles it" do
      expense = Expense.create!(company: company, user: owner, expense_category: category,
                                description: "Rent owed", amount_cents: 30_000,
                                expense_date: Date.current)
      voucher = Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT, treasury: cash, user: owner, amount_cents: 30_000,
        allocations: [{ settles: expense, amount_cents: 30_000 }]
      ).call

      get admin_accounting_expense_path(expense)

      expect(response.body).to include(voucher.number)
      expect(response.body).to include(admin_accounting_voucher_path(voucher))
    end
  end

  describe "income" do
    it "links to the receipt voucher that collected it" do
      income = Income.create!(company: company, user: owner, treasury: cash,
                              income_category: IncomeCategory.create!(name: "Catering",
                                                                      category_type: "catering",
                                                                      position: 1, company: company),
                              description: "Catering", amount_cents: 15_000,
                              income_date: Date.current)
      voucher = income.payment_allocations.sole.payment

      get admin_accounting_income_path(income)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(voucher.number)
    end
  end

  # The screenshot: a supplier payment recorded before payments became vouchers.
  describe "a legacy expense whose source is a VendorInvoicePayment" do
    it "names it instead of printing the Ruby object" do
      supplier = Supplier.create!(name: "لحمه نعيم", lead_time_days: 2, company: company)
      invoice = VendorInvoice.new(supplier: supplier, user: owner,
                                  location: create(:location, company: company),
                                  invoice_number: "VI-2026-00365", invoice_date: Date.current,
                                  received_on: Date.current, company: company)
      invoice.save!(validate: false)
      payment = VendorInvoicePayment.create!(company: company, vendor_invoice: invoice,
                                             user: owner, treasury: cash,
                                             amount_cents: 32_600, payment_date: Date.current)
      expense = Expense.create!(company: company, user: owner, expense_category: category,
                                description: "Vendor invoice VI-2026-00365",
                                amount_cents: 32_600, expense_date: Date.current,
                                is_auto_generated: true, source_record: payment)

      get admin_accounting_expense_path(expense)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("VI-2026-00365")
      expect(response.body).not_to match(/#<VendorInvoicePayment:0x/)
      expect(response.body).not_to include("0x0000")
    end

    it "falls back to a readable name when the source record is gone" do
      expense = Expense.create!(company: company, user: owner, expense_category: category,
                                description: "orphan", amount_cents: 1_000,
                                expense_date: Date.current, is_auto_generated: true,
                                source_record_type: "VendorInvoicePayment",
                                source_record_id: SecureRandom.uuid)

      get admin_accounting_expense_path(expense)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Vendor invoice payment #")
    end
  end
end
