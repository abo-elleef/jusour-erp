# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::ManufacturingTemplates", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:output) { create(:ingredient, company: company, ingredient_category: category, name: "Sauce Base") }
  let!(:input) { create(:ingredient, company: company, ingredient_category: category, name: "Tomato") }

  before do
    Current.company = company
    sign_in owner
  end

  it "renders the new form with searchable ingredient pickers" do
    get new_admin_inventory_manufacturing_template_path
    expect(response).to have_http_status(:ok)
    # Ingredient pickers are the shared searchable-select combobox, wired to the
    # manufacturing-units controller, with options supplied at the form level.
    expect(response.body).to include("data-controller=\"searchable-select\"")
    expect(response.body).to include("manufacturing-units#lineChanged")
    expect(response.body).to include("data-searchable-select-options")
  end

  it "renders the edit form for a template with an input line" do
    template = ManufacturingTemplate.create!(company: company, name: "Sauce", yield_quantity: 1,
      active: false, output_ingredient: output, yield_unit: output.unit)
    template.manufacturing_template_lines.create!(ingredient: input, quantity_used: 2, unit: input.unit)

    get edit_admin_inventory_manufacturing_template_path(template)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("manufacturing-units#outputChanged")
  end

  it "renders the show page without the input-ingredients management section" do
    template = ManufacturingTemplate.create!(company: company, name: "Sauce", yield_quantity: 1,
      active: false, output_ingredient: output, yield_unit: output.unit)
    template.manufacturing_template_lines.create!(ingredient: input, quantity_used: 2, unit: input.unit)
    template.update!(active: true)

    get admin_inventory_manufacturing_template_path(template)
    expect(response).to have_http_status(:ok)
    # The input-lines list/add-line form was moved to the edit form; the show
    # page no longer renders it or its add-line action.
    expect(response.body).not_to include(admin_inventory_manufacturing_template_lines_path(template))
    expect(response.body).to include(I18n.t("inventory.manufacturing.runs.recent"))
  end
end
