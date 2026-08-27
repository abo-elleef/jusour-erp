# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::CustomerInvoices", type: :request do
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

  def line_attrs
    { "0" => { ingredient_id: ingredient.id, quantity: "5", unit: ingredient.unit, unit_price_pounds: "20" } }
  end

  it "lists and opens the new form" do
    get admin_sales_customer_invoices_path
    expect(response).to have_http_status(:ok)
    get new_admin_sales_customer_invoice_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("customer-invoice-lines")
  end

  it "creates a draft" do
    expect {
      post admin_sales_customer_invoices_path, params: {
        commit_action: "draft",
        customer_invoice: { customer_id: customer.id, location_id: location.id,
          invoice_date: Date.current, customer_invoice_lines_attributes: line_attrs }
      }
    }.to change(CustomerInvoice, :count).by(1)

    inv = CustomerInvoice.last
    expect(inv.status).to eq("draft")
    expect(inv.total_cents).to eq(10_000) # 5 × 20.00
    expect(response).to redirect_to(admin_sales_customer_invoice_path(inv))
  end

  it "creates and confirms in one step (raises AR, deducts stock)" do
    post admin_sales_customer_invoices_path, params: {
      commit_action: "confirm",
      customer_invoice: { customer_id: customer.id, location_id: location.id,
        invoice_date: Date.current, customer_invoice_lines_attributes: line_attrs }
    }
    inv = CustomerInvoice.last
    expect(inv.status).to eq("confirmed")
    expect(customer.reload.ar_balance_cents).to eq(10_000)
    expect(ingredient.stock_batches.sum(:quantity_remaining).to_d).to eq(95)
    expect(response).to redirect_to(admin_sales_customer_invoice_path(inv))
  end

  it "records a payment against a confirmed invoice" do
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location, invoice_date: Date.current)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 2_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
    treasury = Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 0, opening_balance_cents: 0, company: company)

    post record_payment_admin_sales_customer_invoice_path(inv), params: { amount: "40", treasury_id: treasury.id }

    expect(customer.reload.ar_balance_cents).to eq(6_000) # 10,000 - 4,000
    expect(treasury.reload.balance_cents).to eq(4_000)
  end

  it "credits the sale to a chosen teammate (for their bonus)" do
    mate = create(:user, company: company, name: "Teammate")
    post admin_sales_customer_invoices_path, params: {
      commit_action: "draft",
      customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
        salesperson_id: mate.id, customer_invoice_lines_attributes: line_attrs }
    }
    expect(CustomerInvoice.last.salesperson).to eq(mate)
    expect(CustomerInvoice.last.user).to eq(owner) # recorder is still the current user
  end

  it "defaults the salesperson to the recorder when none is chosen" do
    post admin_sales_customer_invoices_path, params: {
      commit_action: "draft",
      customer_invoice: { customer_id: customer.id, location_id: location.id, invoice_date: Date.current,
        customer_invoice_lines_attributes: line_attrs }
    }
    expect(CustomerInvoice.last.salesperson).to eq(owner)
  end

  it "is hidden for a restaurant company (feature off)" do
    company.update!(business_type: "restaurant")
    get admin_sales_customer_invoices_path
    expect(response).to redirect_to(admin_root_path)
  end
end
