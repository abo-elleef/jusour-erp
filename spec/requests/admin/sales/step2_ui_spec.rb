# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales step-2 UI", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    sign_in owner
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  describe "price tiers" do
    it "creates a tier" do
      expect {
        post admin_sales_price_tiers_path, params: { price_tier: { name: "Gold", discount_percent: 10, active: "1" } }
      }.to change(PriceTier, :count).by(1)
      expect(PriceTier.last.discount_percent).to eq(10)
    end
  end

  describe "customer credit profile" do
    it "saves credit fields via the customer form (currency inputs → cents)" do
      tier = PriceTier.create!(company: company, name: "Gold", discount_percent: 10)
      cust = create(:customer, company: company)
      patch admin_customer_path(cust), params: {
        customer: { customer_type: "commercial", price_tier_id: tier.id,
          credit_warning_limit_pounds: "1000", credit_hard_limit_pounds: "1500", credit_terms_days: "30" }
      }
      cust.reload
      expect(cust.customer_type).to eq("commercial")
      expect(cust.credit_warning_limit_cents).to eq(100_000)
      expect(cust.credit_hard_limit_cents).to eq(150_000)
      expect(cust.effective_discount_percent).to eq(10)
    end
  end

  describe "statements" do
    it "lists commercial customers and shows an aging statement" do
      inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      Sales::ConfirmCustomerInvoiceService.new(inv, owner).call

      get admin_sales_customer_statements_path
      expect(response.body).to include("Clinic")

      get admin_sales_customer_statement_path(customer)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(inv.invoice_number)
    end

    it "lists every invoiced customer of any type, sorted and searchable, with a total over everyone" do
      walk_in = create(:customer, company: company, name: "Dr Walk-in", customer_type: "regular", phone: "01000000001")
      never_invoiced = create(:customer, company: company, name: "Nobody", customer_type: "regular")
      [[customer, 20_000], [walk_in, 5_000]].each do |cust, price|
        inv = CustomerInvoice.new(company: company, customer: cust, user: owner, location: location, invoice_date: Date.current)
        inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: price)
        inv.save!
        Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
      end
      expect(walk_in.reload.ar_balance_cents).to be_positive

      get admin_sales_customer_statements_path(locale: "en")
      body = response.body
      expect(body).to include("Dr Walk-in", "Clinic", "Regular")
      expect(body).not_to include(never_invoiced.name)
      expect(body.index("Clinic")).to be < body.index("Dr Walk-in") # default: biggest balance first
      expect(body).to include(ApplicationController.helpers.format_money(customer.reload.ar_balance_cents + walk_in.ar_balance_cents))

      get admin_sales_customer_statements_path(sort: "balance", dir: "asc", locale: "en")
      expect(response.body.index("Dr Walk-in")).to be < response.body.index("Clinic")

      get admin_sales_customer_statements_path(query: "0100000", locale: "en")
      expect(response.body).to include("Dr Walk-in")
      expect(response.body).not_to include(">Clinic<")

      get admin_sales_customer_statements_path(sort: "bogus; DROP TABLE x", locale: "en")
      expect(response).to have_http_status(:ok)
    end

    it "records a customer-level payment by receipt voucher, oldest invoice first" do
      inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
      treasury = Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 0, opening_balance_cents: 0, company: company)

      oldest_first = Admin::Accounting::VouchersController::OLDEST_FIRST
      get admin_sales_customer_statement_path(customer)
      link = new_admin_accounting_voucher_path(direction: Voucher::RECEIPT, party: "Customer:#{customer.id}", settles: oldest_first)
      expect(response.body).to include(ERB::Util.html_escape(link))

      post admin_accounting_vouchers_path, params: {
        voucher: { direction: Voucher::RECEIPT, treasury_id: treasury.id, amount_pounds: "500",
                   voucher_date: Date.current.to_s, party_selection: "Customer:#{customer.id}" },
        settles: oldest_first
      }
      expect(customer.reload.ar_balance_cents).to eq(50_000) # 100,000 - 50,000
      expect(inv.reload.amount_paid_cents).to eq(50_000)
      expect(treasury.reload.balance_cents).to eq(50_000)
    end

    it "keeps an overpayment on the customer's account" do
      inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      Sales::ConfirmCustomerInvoiceService.new(inv, owner).call # AR 20,000
      treasury = Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 0, opening_balance_cents: 0, company: company)

      post admin_accounting_vouchers_path, params: {
        voucher: { direction: Voucher::RECEIPT, treasury_id: treasury.id, amount_pounds: "300",
                   voucher_date: Date.current.to_s, party_selection: "Customer:#{customer.id}" },
        settles: Admin::Accounting::VouchersController::OLDEST_FIRST
      }

      expect(inv.reload.payment_status).to eq("paid")
      expect(customer.reload.ar_balance_cents).to eq(-10_000) # 20,000 owed, 30,000 paid
      expect(Voucher.last.payment_allocations.map(&:settles)).to eq([inv, customer])
    end
  end

  describe "credit notes" do
    it "creates and confirms a credit note that reduces AR and restocks" do
      inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
      inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
      inv.save!
      Sales::ConfirmCustomerInvoiceService.new(inv, owner).call # AR 100,000, stock 95

      post admin_sales_credit_notes_path, params: {
        commit_action: "confirm",
        credit_note: { customer_id: customer.id, location_id: location.id, restock: "1",
          credit_note_date: Date.current,
          credit_note_lines_attributes: { "0" => { ingredient_id: ingredient.id, quantity: "2", unit: ingredient.unit, unit_price_pounds: "200" } } }
      }
      cn = CreditNote.last
      expect(cn.status).to eq("confirmed")
      expect(customer.reload.ar_balance_cents).to eq(60_000) # 100,000 - 40,000
      expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(97) # 95 + 2 restocked
    end
  end

  it "blocks the whole sales area for a restaurant company" do
    company.update!(business_type: "restaurant")
    get admin_sales_price_tiers_path
    expect(response).to redirect_to(admin_root_path)
  end
end
