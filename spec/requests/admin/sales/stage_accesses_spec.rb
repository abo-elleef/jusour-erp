# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::StageAccesses", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "regular") }
  let(:warehouse_role) do
    Role.create!(company: company, name: "Warehouse", key: "warehouse", permissions: %w[customers:manage sales:dispatch])
  end
  let(:warehouse) { create(:user, company: company, role: "custom", role_id: warehouse_role.id) }

  before { Current.company = company }

  def grid_params(see:, notify: [])
    CustomerInvoice::STAGES.index_with do |stage|
      { "see" => see.include?(stage) ? "1" : "0", "notify" => notify.include?(stage) ? "1" : "0" }
    end
  end

  it "shows the grid to the owner and saves it" do
    warehouse_role
    sign_in owner

    get admin_sales_stage_access_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Warehouse")

    patch admin_sales_stage_access_path, params: { grid: { warehouse_role.id => grid_params(
      see: %w[waiting_for_shipping shipped], notify: %w[waiting_for_shipping historical]) } }

    expect(response).to redirect_to(admin_sales_stage_access_path)
    rows = Sales::StageAccess.where(role: warehouse_role).index_by(&:stage)
    expect(rows.size).to eq(CustomerInvoice::STAGES.size)
    expect(rows["waiting_for_shipping"]).to have_attributes(can_see: true, notify: true)
    expect(rows["draft"]).to have_attributes(can_see: false, notify: false)
    expect(rows["historical"].notify).to be(false) # never notifies imported history
  end

  it "keeps everyone but the owner out" do
    sign_in create(:user, company: company, role: "manager")

    get admin_sales_stage_access_path
    expect(response).to redirect_to(admin_sales_customer_invoices_path)

    patch admin_sales_stage_access_path, params: { grid: { warehouse_role.id => grid_params(see: []) } }
    expect(Sales::StageAccess.count).to eq(0)
  end

  it "filters the invoice list and blocks an invoice page at a hidden stage" do
    CustomerInvoice::STAGES.each do |stage|
      Sales::StageAccess.create!(role: warehouse_role, stage: stage, can_see: stage == "waiting_for_shipping")
    end
    draft = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current)
    draft.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 1_000)
    draft.save!

    sign_in warehouse
    get admin_sales_customer_invoices_path
    expect(response.body).not_to include(draft.invoice_number)

    get admin_sales_customer_invoice_path(draft)
    expect(response).to redirect_to(admin_sales_customer_invoices_path)
  end

  it "sends an approver back to the approvals queue when the approved invoice leaves their view" do
    wallet_role = Role.create!(company: company, name: "Wallet", key: "wallet", permissions: %w[customers:manage])
    saif = create(:user, company: company, role: "custom", role_id: wallet_role.id)
    CustomerInvoice::STAGES.each do |stage|
      Sales::StageAccess.create!(role: wallet_role, stage: stage, can_see: stage == "pending_payment_confirmation")
    end
    treasury = Treasury.create!(name: "Wallet", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
    method = create(:sales_payment_method, company: company, treasury: treasury)
    method.approvers << saif
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 10, quantity_remaining: 10,
      cost_per_unit_cents: 100, received_on: Date.current)
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current, payment_method: "online", sales_payment_method: method)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 1_000)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, owner).call

    sign_in saif
    post approve_payment_admin_sales_customer_invoice_path(inv)

    expect(inv.reload.status).to eq("confirmed")
    expect(response).to redirect_to(admin_sales_customer_invoices_path(status: "pending_payment_confirmation"))
    expect(flash[:notice]).to be_present
  end
end
