# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::VendorInvoices export", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Olive Oil") }

  before do
    Current.company = company
    sign_in owner
  end

  def invoice_with_line
    invoice = VendorInvoice.create!(
      supplier: supplier, user: owner, location: location,
      invoice_date: Date.current, received_on: Date.current, company: company
    )
    invoice.vendor_invoice_lines.create!(ingredient: ingredient, quantity: 3, line_total_cents: 900)
    invoice
  end

  it "exports the invoice as an Excel-friendly CSV with a UTF-8 BOM" do
    invoice = invoice_with_line

    get export_admin_inventory_vendor_invoice_path(invoice, format: :csv)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("#{invoice.invoice_number}.csv")
    expect(response.body.bytes.first(3)).to eq([0xEF, 0xBB, 0xBF]) # UTF-8 BOM
    body = response.body.dup.force_encoding("UTF-8")
    expect(body).to include(invoice.invoice_number)
    expect(body).to include("Olive Oil")
  end
end
