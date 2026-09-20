# frozen_string_literal: true

require "rails_helper"

# The voucher index and document render whatever a voucher settled. That is a
# growing list, and the pages took a NoMethodError in production the first time
# a voucher paid a supplier invoice — an invoice has no `description`, and does
# not live under admin/accounting where the views were building paths.
#
# So these render both pages against every settleable type there is, driven by
# PaymentAllocation::SETTLEABLE_TYPES rather than a hand-written list: adding a
# type without teaching the views about it fails here.
RSpec.describe "Voucher pages render whatever was settled", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 500_000,
                     opening_balance_cents: 500_000, company: company)
  end

  before { sign_in owner }

  # A voucher settling one record of the given type, built without going through
  # the posting service so every type can be covered uniformly.
  def voucher_settling(record, direction: Voucher::PAYMENT)
    voucher = Voucher.create!(company: company, direction: direction, treasury: cash,
                              user: owner, amount_cents: 1_000, voucher_date: Date.current)
    PaymentAllocation.create!(company: company, payment: voucher,
                              settles: record, amount_cents: 1_000)
    voucher
  end

  PaymentAllocation::SETTLEABLE_TYPES.each do |type|
    context "a voucher settling a #{type}" do
      it "renders the index" do
        voucher_settling(settleable(type))

        get admin_accounting_vouchers_path(start_date: Date.current.beginning_of_year,
                                           end_date: Date.current)

        expect(response).to have_http_status(:ok)
      end

      it "renders the document" do
        voucher = voucher_settling(settleable(type))

        get admin_accounting_voucher_path(voucher)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(voucher.number)
      end

      it "exports to CSV" do
        voucher_settling(settleable(type))

        get admin_accounting_vouchers_path(format: :csv,
                                           start_date: Date.current.beginning_of_year,
                                           end_date: Date.current)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  it "renders a voucher that settled nothing at all" do
    voucher = Voucher.create!(company: company, direction: Voucher::RECEIPT, treasury: cash,
                              user: owner, amount_cents: 1_000, voucher_date: Date.current)

    get admin_accounting_voucher_path(voucher)
    expect(response).to have_http_status(:ok)

    get admin_accounting_vouchers_path
    expect(response).to have_http_status(:ok)
  end

  def settleable(type)
    case type
    when "Expense"
      Expense.create!(company: company, user: owner, description: "Rent", amount_cents: 5_000,
                      expense_date: Date.current,
                      expense_category: ExpenseCategory.create!(name: "Rent", category_type: "rent",
                                                                position: 1, company: company))
    when "Income"
      Income.create!(company: company, user: owner, description: "Catering", amount_cents: 5_000,
                     income_date: Date.current,
                     income_category: IncomeCategory.create!(name: "Catering", category_type: "catering",
                                                             position: 1, company: company))
    when "VendorInvoice"
      supplier = Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company)
      inv = VendorInvoice.new(supplier: supplier, user: owner, location: create(:location, company: company),
                              invoice_number: "INV-7777", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.save!(validate: false)
      inv
    when "CustomerInvoice"
      CustomerInvoice.create!(company: company, customer: create(:customer, company: company),
                              user: owner, location: create(:location, company: company),
                              invoice_date: Date.current)
    when "PayrollAdvance"
      staff = create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
      PayrollAdvance.create!(company: company, user: staff, paid_by: owner,
                             treasury: Treasury.create!(company: company, name: "Adv Safe #{SecureRandom.hex(3)}",
                                                        treasury_type: "safe", opening_balance_cents: 100_000,
                                                        balance_cents: 100_000),
                             amount_cents: 10_000, paid_on: Date.current)
    when "Customer" then create(:customer, company: company)
    when "Supplier" then Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company)
    else raise "no fixture for settleable type #{type}"
    end
  end

  describe "a voided voucher" do
    let(:category) do
      ExpenseCategory.create!(name: "Rent", category_type: "rent", position: 1, company: company)
    end

    # Editing the expense voids the voucher that paid it and issues a
    # replacement, so both states exist to render.
    def superseded_pair
      expense = Expense.create!(company: company, user: owner, treasury: cash,
                                expense_category: category, description: "Rent",
                                amount_cents: 20_000, expense_date: Date.current)
      original = Voucher.sole
      expense.update!(amount_cents: 25_000)
      [original.reload, Voucher.active.sole]
    end

    it "renders the voided document, saying so and naming its replacement" do
      original, replacement = superseded_pair

      get admin_accounting_voucher_path(original)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.vouchers.voided_banner"))
      expect(response.body).to include(replacement.number)
    end

    it "renders the replacement, pointing back at what it replaced" do
      original, replacement = superseded_pair

      get admin_accounting_voucher_path(replacement)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.vouchers.replaces"))
      expect(response.body).to include(original.number)
    end

    it "lists it, marked, and leaves it out of the totals" do
      original, replacement = superseded_pair

      get admin_accounting_vouchers_path(start_date: Date.current.beginning_of_year,
                                         end_date: Date.current)

      expect(response.body).to include(original.number)
      expect(response.body).to include(I18n.t("accounting.vouchers.voided"))
      # Only the live document counts toward what was paid — asserted on the
      # scope rather than the rendered figure, which is formatted per locale.
      expect(Voucher.active.payments.sum(:amount_cents)).to eq(replacement.amount_cents)
      expect(Voucher.sum(:amount_cents)).to eq(original.amount_cents + replacement.amount_cents)
    end

    it "exports both to CSV" do
      superseded_pair

      get admin_accounting_vouchers_path(format: :csv,
                                         start_date: Date.current.beginning_of_year,
                                         end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.vouchers.voided"))
      expect(response.body).to include(I18n.t("accounting.vouchers.live"))
    end
  end
end
