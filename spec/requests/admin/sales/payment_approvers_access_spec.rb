# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales payment approval by method", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, company: company, role: "manager") }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:treasury) do
    Treasury.create!(name: "Saif wallet", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
  end
  let(:payment_method) { create(:sales_payment_method, company: company, treasury: treasury, name: "Vodafone Cash Saif") }
  let(:saif) do
    role = Role.create!(company: company, name: "Wallet holder", key: "wallet_holder", permissions: %w[customers:manage])
    create(:user, company: company, role: "custom", role_id: role.id)
  end

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
    payment_method.approvers << saif
  end

  def pending_invoice
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current, payment_method: "online", sales_payment_method: payment_method)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
    inv
  end

  it "lets the method's approver approve, even without sales:confirm_payments" do
    inv = pending_invoice
    sign_in saif

    get admin_sales_customer_invoice_path(inv)
    expect(response.body).to include(approve_payment_admin_sales_customer_invoice_path(inv))

    post approve_payment_admin_sales_customer_invoice_path(inv)
    expect(inv.reload.status).to eq("confirmed")
    expect(treasury.reload.balance_cents).to eq(100_000)
  end

  it "stops a confirm_payments holder who isn't this method's approver" do
    inv = pending_invoice
    sign_in manager

    get admin_sales_customer_invoice_path(inv)
    expect(response.body).not_to include(approve_payment_admin_sales_customer_invoice_path(inv))

    post approve_payment_admin_sales_customer_invoice_path(inv)
    expect(inv.reload.status).to eq("pending_payment_confirmation")

    post reject_payment_admin_sales_customer_invoice_path(inv)
    expect(inv.reload.status).to eq("pending_payment_confirmation")
  end

  it "shows the approvals link to the assigned approver" do
    sign_in saif
    get admin_sales_customer_invoices_path
    expect(response.body).to include(I18n.t("sales.nav.payment_approvals"))
  end
end
