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
    expect(response.body).to include(I18n.t("inventory.stock_transfers.order_limit"))
    expect(response.body).to include(I18n.t("inventory.stock_transfers.counted_quantity"))
    expect(response.body).to include('value="10.0"')
    expect(response.body).to include("[order_limit]")
    expect(response.body).not_to match(/quantity_requested_input"[^>]*value="10/)
    expect(response.body).not_to match(/value="10[^"]*"[^>]*quantity_requested_input/)
  end

  it "allows the same ingredient on multiple template lines" do
    post admin_inventory_stock_transfer_templates_path, params: {
      stock_transfer_template: {
        name: "Duplicate lines ok",
        active: true,
        default_from_location_id: kitchen.id,
        default_to_location_id: branch.id,
        stock_transfer_template_lines_attributes: {
          "0" => { ingredient_id: ingredient.id, default_quantity: 5, unit: ingredient.unit, position: 0 },
          "1" => { ingredient_id: ingredient.id, default_quantity: 10, unit: ingredient.unit, position: 1 }
        }
      }
    }

    expect(response).to redirect_to(admin_inventory_stock_transfer_template_path(StockTransferTemplate.last))
    template = StockTransferTemplate.last
    expect(template.stock_transfer_template_lines.map(&:ingredient_id)).to eq([ingredient.id, ingredient.id])
  end

  it "show page supports sorting and highlights repeated ingredients" do
    template = StockTransferTemplate.create!(
      company: company, name: "Dupes", active: true,
      default_from_location: kitchen, default_to_location: branch
    )
    other = create(:ingredient, company: company, name: "Zucchini")
    StockTransferTemplateLine.create!(
      stock_transfer_template: template, ingredient: ingredient, default_quantity: 5, position: 0
    )
    StockTransferTemplateLine.create!(
      stock_transfer_template: template, ingredient: ingredient, default_quantity: 10, position: 1
    )
    StockTransferTemplateLine.create!(
      stock_transfer_template: template, ingredient: other, default_quantity: 3, position: 2
    )

    get admin_inventory_stock_transfer_template_path(template, sort: "ingredient")
    expect(response).to be_successful
    expect(response.body).to include(I18n.t("inventory.stock_transfer_templates.repeated"))
    expect(response.body).to include(admin_inventory_ingredient_path(ingredient))

    get admin_inventory_stock_transfer_template_path(template, grouped: 1, sort: "order_limit", dir: "desc")
    expect(response).to be_successful
    expect(response.body).to include(I18n.t("inventory.stock_transfers.group_by_category"))
  end
end
