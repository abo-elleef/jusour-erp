# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::ImportShipments", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Importer", lead_time_days: 5, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:product) { create(:ingredient, company: company, ingredient_category: category, name: "Drill", unit: "kg") }
  let(:treasury) { Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 1_000_000, opening_balance_cents: 1_000_000, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  def shipment_with_batch(qty:, cost_cents:)
    shipment = ImportShipment.create!(company: company, user: owner, location: location, arrival_date: Date.current)
    vi = VendorInvoice.create!(company: company, supplier: supplier, user: owner, location: location,
      invoice_number: "VI-#{SecureRandom.hex(3)}", invoice_date: Date.current, received_on: Date.current, import_shipment: shipment)
    line = vi.vendor_invoice_lines.create!(ingredient: product, quantity: qty, unit: product.unit, line_total_cents: qty * cost_cents)
    StockBatch.create!(ingredient: product, location: location, vendor_invoice_line: line,
      quantity_received: qty, quantity_remaining: qty, cost_per_unit_cents: cost_cents, received_on: Date.current)
    shipment
  end

  it "lists, opens the new form, and creates a shipment" do
    get admin_inventory_import_shipments_path
    expect(response).to have_http_status(:ok)
    get new_admin_inventory_import_shipment_path
    expect(response).to have_http_status(:ok)

    expect {
      post admin_inventory_import_shipments_path, params: { import_shipment: { location_id: location.id, arrival_date: Date.current } }
    }.to change(ImportShipment, :count).by(1)
  end

  it "adds a landed cost (cash-out) and shows the allocation" do
    shipment = shipment_with_batch(qty: 10, cost_cents: 10_000)

    post add_cost_admin_inventory_import_shipment_path(shipment),
      params: { cost_type: "customs", amount: "800", treasury_id: treasury.id }

    expect(shipment.reload.total_costs_cents).to eq(80_000)
    expect(treasury.reload.balance_cents).to eq(920_000)

    get admin_inventory_import_shipment_path(shipment)
    expect(response.body).to include("Drill")
  end

  it "finalizes and writes the landed unit cost onto the product batch" do
    shipment = shipment_with_batch(qty: 10, cost_cents: 10_000)
    ShipmentCost.create!(import_shipment: shipment, user: owner, cost_type: "customs", amount_cents: 80_000, incurred_on: Date.current)

    post finalize_admin_inventory_import_shipment_path(shipment)

    batch = shipment.stock_batches.first
    # Single product absorbs the whole 80,000 pool: 10,000 + 80,000/10 = 18,000.
    expect(batch.cost_per_unit_cents).to eq(18_000)
    expect(shipment.reload).to be_finalized
  end

  it "attaches and detaches a goods invoice" do
    shipment = ImportShipment.create!(company: company, user: owner, location: location)
    vi = VendorInvoice.create!(company: company, supplier: supplier, user: owner, location: location,
      invoice_number: "VI-FREE", invoice_date: Date.current, received_on: Date.current)

    post attach_invoice_admin_inventory_import_shipment_path(shipment), params: { vendor_invoice_id: vi.id }
    expect(vi.reload.import_shipment).to eq(shipment)

    delete detach_invoice_admin_inventory_import_shipment_path(shipment), params: { vendor_invoice_id: vi.id }
    expect(vi.reload.import_shipment).to be_nil
  end

  it "is blocked when landed_cost is off (restaurant)" do
    company.update!(business_type: "restaurant")
    get admin_inventory_import_shipments_path
    expect(response).to redirect_to(admin_root_path)
  end
end
