# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::ManufacturingRuns index", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company) }
  let(:input) { create(:ingredient, company: company, ingredient_category: category, name: "Tomato") }
  let(:output) { create(:ingredient, company: company, ingredient_category: category, name: "Sauce") }
  let(:day) { Date.current }

  def active_template(name: "Sauce Template", yield_qty: 2)
    template = ManufacturingTemplate.create!(
      company: company, name: name, yield_quantity: yield_qty,
      active: false, output_ingredient: output, yield_unit: output.unit
    )
    template.manufacturing_template_lines.create!(ingredient: input, quantity_used: 1, unit: input.unit)
    template.update!(active: true)
    template
  end

  def create_run!(template:, runs_count:, notes: nil, reversed_at: nil, occurred_on: day)
    ManufacturingRun.create!(
      company: company,
      manufacturing_template: template,
      user: owner,
      location: kitchen,
      runs_count: runs_count,
      occurred_on: occurred_on,
      shelf_life_days: 3,
      notes: notes,
      reversed_at: reversed_at,
      reversed_by: reversed_at ? owner : nil
    )
  end

  before do
    Current.company = company
    sign_in owner
  end

  it "shows the per-run history by default" do
    template = active_template
    run = create_run!(template: template, runs_count: 2)

    get admin_inventory_manufacturing_runs_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.manufacturing.runs.view_runs"))
    expect(response.body).to include(I18n.t("inventory.manufacturing.runs.view_daily"))
    expect(response.body).to include(run.run_number)
    expect(response.body).to include(template.name)
  end

  it "groups daily production by output and sums quantities" do
    t1 = active_template(name: "Sauce A", yield_qty: 2)
    t2 = active_template(name: "Sauce B", yield_qty: 3)
    create_run!(template: t1, runs_count: 2, notes: "Morning batch")
    create_run!(template: t2, runs_count: 1, notes: "Afternoon")

    get admin_inventory_manufacturing_runs_path(view: "daily", date: day.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.manufacturing.runs.card_title"))
    expect(response.body).to include(I18n.t("inventory.manufacturing.runs.card_count"))
    expect(response.body).to include("Sauce")
    expect(response.body).to include("Morning batch")
    expect(response.body).to include("Afternoon")
    expect(response.body).to match(/>\s*7\s*</) # (2*2)+(1*3)
  end

  it "excludes reversed runs from daily totals" do
    template = active_template(yield_qty: 5)
    create_run!(template: template, runs_count: 2, notes: "Kept")
    create_run!(template: template, runs_count: 10, notes: "Undone", reversed_at: Time.current)

    get admin_inventory_manufacturing_runs_path(view: "daily", date: day.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Kept")
    expect(response.body).not_to include("Undone")
    expect(response.body).to match(/>\s*10\s*</) # 2 * 5 only
  end

  it "shows empty state when the day has no production" do
    get admin_inventory_manufacturing_runs_path(view: "daily", date: day.iso8601)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("inventory.manufacturing.runs.daily_empty", date: I18n.l(day, format: :long)))
  end
end
