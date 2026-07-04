# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::Suppliers deletion", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 0.0) }

  before do
    Current.company = company
    sign_in owner
  end

  it "permanently deletes a supplier with no history, along with its empty AP treasury" do
    supplier = Supplier.create!(name: "Empty Co", company: company)
    treasury = supplier.ap_treasury

    expect do
      delete admin_inventory_supplier_path(supplier)
    end.to change(Supplier, :count).by(-1)

    expect(response).to redirect_to(admin_inventory_suppliers_path)
    expect(Treasury.exists?(treasury.id)).to be(false)
  end

  it "refuses to delete a supplier that has invoices" do
    supplier = Supplier.create!(name: "Has Invoices", company: company)
    invoice = VendorInvoice.new(
      supplier: supplier, user: owner, location: location, invoice_number: "VI-KEEP",
      invoice_date: Date.current, received_on: Date.current, company: company
    )
    invoice.vendor_invoice_lines.build(ingredient: ingredient, quantity: 1, line_total_cents: 500_00)
    invoice.save!

    expect do
      delete admin_inventory_supplier_path(supplier)
    end.not_to change(Supplier, :count)

    expect(response).to redirect_to(admin_inventory_supplier_path(supplier))
    expect(flash[:alert]).to be_present
  end
end
