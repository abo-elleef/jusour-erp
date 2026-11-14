# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales shipping track", type: :request do
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
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 100,
      quantity_remaining: 100, cost_per_unit_cents: 1_000, received_on: Date.current)
  end

  def custom_user(*permissions)
    role = Role.create!(company: company, name: "Sales #{permissions.size}", key: "sales_#{SecureRandom.hex(3)}",
      permissions: permissions)
    create(:user, company: company, role: "custom", role_id: role.id)
  end

  def confirmed_delivery
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current, payment_method: "cash_on_delivery", fulfillment_method: "delivery",
      shipping_company: shipping_company)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 5, unit: ingredient.unit, unit_price_cents: 20_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call
    inv
  end

  it "lets the owner dispatch and then mark delivered" do
    sign_in owner
    inv = confirmed_delivery

    post mark_dispatched_admin_sales_customer_invoice_path(inv)
    expect(inv.reload.shipping_status).to eq("shipped")

    post complete_shipping_admin_sales_customer_invoice_path(inv)
    expect(response).to redirect_to(admin_sales_customer_invoice_path(inv))
    expect(inv.reload.shipping_status).to eq("shipping_completed")
    expect(inv.shipping_completed_by).to eq(owner)
  end

  it "only lets a holder of sales:complete_shipping mark delivered" do
    inv = confirmed_delivery
    Sales::DispatchCustomerInvoiceService.new(inv, owner).call

    sign_in custom_user("customers:manage", "sales:dispatch")
    get admin_sales_customer_invoice_path(inv)
    expect(response.body).not_to include(complete_shipping_admin_sales_customer_invoice_path(inv))

    post complete_shipping_admin_sales_customer_invoice_path(inv)
    expect(inv.reload.shipping_status).to eq("shipped")
  end

  it "only lets a holder of sales:dispatch hand it to the courier" do
    inv = confirmed_delivery
    sign_in custom_user("customers:manage", "sales:complete_shipping")

    get admin_sales_customer_invoice_path(inv)
    expect(response.body).not_to include(mark_dispatched_admin_sales_customer_invoice_path(inv))

    post mark_dispatched_admin_sales_customer_invoice_path(inv)
    expect(inv.reload.dispatched_at).to be_nil
    expect(shipping_company.reload.balance_cents).to eq(0)
  end

  it "filters the list by shipping status" do
    sign_in owner
    waiting = confirmed_delivery
    shipped = confirmed_delivery
    Sales::DispatchCustomerInvoiceService.new(shipped, owner).call

    get admin_sales_customer_invoices_path(shipping: "waiting_for_shipping")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(waiting.invoice_number)
    expect(response.body).not_to include(shipped.invoice_number)
  end
end
