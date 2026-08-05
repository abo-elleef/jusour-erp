# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::VendorInvoices navigation", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "links to the previous (newer) and next (older) invoices" do
    older = VendorInvoice.create!(
      supplier: supplier, user: owner, location: location,
      invoice_date: Date.new(2026, 5, 1), received_on: Date.new(2026, 5, 1), company: company
    )
    current = VendorInvoice.create!(
      supplier: supplier, user: owner, location: location,
      invoice_date: Date.new(2026, 6, 1), received_on: Date.new(2026, 6, 1), company: company
    )
    newer = VendorInvoice.create!(
      supplier: supplier, user: owner, location: location,
      invoice_date: Date.new(2026, 7, 1), received_on: Date.new(2026, 7, 1), company: company
    )

    get admin_inventory_vendor_invoice_path(current)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_inventory_vendor_invoice_path(newer))
    expect(response.body).to include(admin_inventory_vendor_invoice_path(older))
  end
end
