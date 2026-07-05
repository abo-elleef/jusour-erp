# frozen_string_literal: true

require "rails_helper"

# Regression: the shared searchable_select partial referenced `html` directly,
# which crashed callers (e.g. stock transfers) that don't pass an html: local.
RSpec.describe "shared/searchable_select rendering", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let!(:branch) { create(:location, company: company, name: "Branch A") }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category) }

  before do
    Current.company = company
    sign_in owner
  end

  it "renders the new stock transfer form (caller without an html: local)" do
    get new_admin_inventory_stock_transfer_path
    expect(response).to have_http_status(:ok)
  end

  it "renders the new vendor invoice form (caller passing an html: local)" do
    Supplier.create!(name: "Fresh Farms", company: company)
    get new_admin_inventory_vendor_invoice_path
    expect(response).to have_http_status(:ok)
  end
end
