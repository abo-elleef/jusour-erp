# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin inventory stock transfer templates", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:user) { create(:user, company: company, role: "owner") }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch") }
  let(:ingredient) { create(:ingredient, company: company, name: "Flour") }

  before do
    Current.company = company
    sign_in user
  end

  it "creates a template and boots a new transfer from it" do
    post admin_inventory_stock_transfer_templates_path, params: {
      stock_transfer_template: {
        name: "Weekly restock",
        active: true,
        default_from_location_id: kitchen.id,
        default_to_location_id: branch.id,
        stock_transfer_template_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, default_quantity: 10, unit: ingredient.unit }
        }
      }
    }
    expect(response).to redirect_to(admin_inventory_stock_transfer_template_path(StockTransferTemplate.last))
    template = StockTransferTemplate.last
    expect(template.stock_transfer_template_lines.size).to eq(1)

    get new_admin_inventory_stock_transfer_path(template_id: template.id)
    expect(response).to be_successful
    expect(response.body).to include("Flour")
    expect(response.body).to include("Weekly restock")
  end
end
