# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bulk manufacturing run recording", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:input) { create(:ingredient, company: company, ingredient_category: category, name: "Bulk Tomato") }
  let(:output) { create(:ingredient, company: company, ingredient_category: category, name: "Bulk Sauce") }

  before do
    Current.company = company
    sign_in owner
    input.ingredient_locations.create!(location: kitchen, quantity_on_hand: 10, reorder_threshold: 0)
    StockBatch.create!(
      ingredient: input, location: kitchen,
      quantity_received: 10, quantity_remaining: 10,
      cost_per_unit_cents: 100, received_on: Date.current
    )
  end

  def active_template
    template = ManufacturingTemplate.create!(company: company, name: "Bulk Sauce", yield_quantity: 2,
      active: false, output_ingredient: output, yield_unit: output.unit)
    template.manufacturing_template_lines.create!(ingredient: input, quantity_used: 1, unit: input.unit)
    template.update!(active: true)
    template
  end

  it "renders the excel-style bulk sheet" do
    active_template

    get new_admin_inventory_manufacturing_run_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("production.bulk.warning_title"))
    expect(response.body).to include("data-controller=\"bulk-manufacturing\"")
    expect(response.body).to include("Bulk Sauce")
  end

  it "records filled rows and skips blanks" do
    template = active_template

    expect {
      post admin_inventory_manufacturing_runs_path, params: {
        bulk: {
          location_id: kitchen.id,
          occurred_on: Date.current.to_s,
          rows: {
            template.id.to_s => {
              template_id: template.id,
              runs_count: "2",
              shelf_life_days: "5"
            }
          }
        }
      }
    }.to change(ManufacturingRun, :count).by(1)

    expect(response).to redirect_to(admin_inventory_manufacturing_runs_path)
    run = ManufacturingRun.last
    expect(run.runs_count.to_d).to eq(2)
    expect(run.location).to eq(kitchen)
    expect(output.reload.quantity_on_hand.to_d).to eq(4)
  end

  it "records nothing when every quantity is blank" do
    template = active_template

    expect {
      post admin_inventory_manufacturing_runs_path, params: {
        bulk: {
          location_id: kitchen.id,
          occurred_on: Date.current.to_s,
          rows: {
            template.id.to_s => { template_id: template.id, runs_count: "" }
          }
        }
      }
    }.not_to change(ManufacturingRun, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t("production.bulk.none_filled"))
  end
end
