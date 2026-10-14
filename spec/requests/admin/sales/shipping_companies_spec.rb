# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Admin::Sales::ShippingCompanies", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:shipping_company) { create(:shipping_company, company: company) }

  before do
    Current.company = company
    sign_in owner
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def dispatch_a_cod_invoice(fee_cents: 10_000)
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current, payment_method: "cash_on_delivery", fulfillment_method: "delivery",
      shipping_company: shipping_company, standard_delivery_fee_cents: fee_cents, delivery_fee_cents: fee_cents)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
    Sales::DispatchCustomerInvoiceService.new(inv, owner).call
    inv
  end

  it "shows no transactions before any invoice has dispatched through this company" do
    get admin_sales_shipping_company_path(shipping_company)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("sales.shipping_companies.statement.no_treasury_yet"))
  end

  it "lists every transaction that built the balance, each linking back to its invoice" do
    invoice = dispatch_a_cod_invoice

    get admin_sales_shipping_company_path(shipping_company)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_sales_customer_invoice_path(invoice))
    expect(response.body).to include(invoice.invoice_number)
  end

  it "exports the statement as a CSV, oldest first, carrying each running balance" do
    dispatch_a_cod_invoice

    get admin_sales_shipping_company_path(shipping_company, format: :csv)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body, headers: true)
    expect(rows.size).to eq(2)
    # The fee-payable entry posts first in the same transaction, so it's the
    # earliest by created_at — oldest-first csv order surfaces it first.
    expect(rows.map { |r| r[4].to_f }).to eq([-100.0, 1000.0])
  end
end
