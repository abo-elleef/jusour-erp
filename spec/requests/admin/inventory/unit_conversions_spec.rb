# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Unit conversion review", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }

  # Ahead of the let! records below: they need the tenant set to resolve units.
  before { Current.company = company }

  let!(:wrong) do
    ingredient = create(:ingredient, company: company, ingredient_category: category, name: "Mushrooms", unit: "kg")
    ingredient.ingredient_units.create!(unit: "g", base_units_per_unit: 430, company: company)
  end

  let!(:right) do
    ingredient = create(:ingredient, company: company, ingredient_category: category, name: "Salt", unit: "kg")
    ingredient.ingredient_units.create!(unit: "g", base_units_per_unit: 0.001, company: company)
  end

  let!(:bare) do
    create(:ingredient, company: company, ingredient_category: category, name: "Carrots", unit: "kg")
  end

  before { sign_in owner }

  it "lists every conversion with the rate that disagrees flagged" do
    get admin_inventory_unit_conversions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Mushrooms")
    expect(response.body).to include("Salt")
    expect(response.body).to include(I18n.t("inventory.unit_conversions.status.check"))
    expect(response.body).to include("430")
  end

  it "narrows to the rates that need a look" do
    get admin_inventory_unit_conversions_path(flag: "check")

    expect(response.body).to include("Mushrooms")
    expect(response.body).not_to include(">Salt<")
  end

  it "lists ingredients that have no alternate unit at all" do
    get admin_inventory_unit_conversions_path(view: "missing")

    expect(response.body).to include("Carrots")
    expect(response.body).not_to include(">Mushrooms<")
  end

  it "exports the review, reasons included, as CSV" do
    get admin_inventory_unit_conversions_path(format: :csv, flag: "check")

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Mushrooms")
    expect(response.body).to include("0.001") # the rate the units imply
    expect(response.body).not_to include("<bdi>") # markup belongs on the page, not in the file
  end

  describe "correcting rates in bulk" do
    it "saves the rows that changed and leaves the rest alone" do
      untouched_at = right.updated_at

      patch bulk_update_admin_inventory_unit_conversions_path, params: {
        conversions: {
          wrong.id => { base_units_per_unit: "0.001", purchase_unit: "0" },
          right.id => { base_units_per_unit: "0.001", purchase_unit: "0" }
        }
      }

      expect(wrong.reload.base_units_per_unit.to_d).to eq(0.001)
      expect(right.reload.updated_at).to eq(untouched_at)
    end

    it "records the rate change in the ingredient's history" do
      patch bulk_update_admin_inventory_unit_conversions_path, params: {
        conversions: { wrong.id => { base_units_per_unit: "0.001" } }
      }

      audit = wrong.ingredient.audits.reorder(:version).last
      expect(audit.action).to eq("unit_rate_changed")
      expect(audit.audited_changes["base_units_per_unit"]).to eq(["430.0", "0.001"])
    end

    it "reports a rate the model rejects instead of saving it" do
      patch bulk_update_admin_inventory_unit_conversions_path,
        params: { conversions: { wrong.id => { base_units_per_unit: "0" } } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("inventory.unit_conversions.save_failed"))
      expect(wrong.reload.base_units_per_unit.to_d).to eq(430)
    end

    it "moves a saved row out of the flagged count in the same response" do
      patch bulk_update_admin_inventory_unit_conversions_path,
        params: { flag: "check", conversions: { wrong.id => { base_units_per_unit: "0.001" } } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("conversion_summary")
      expect(response.body).to include(I18n.t("inventory.unit_conversions.saved", count: 1))
    end

    it "turns away a user who may read inventory but not reshape it" do
      manager = create(:user, :manager, company: company)
      role = Role.unscoped.find_by(company_id: company.id, key: "manager")
      role.update!(permissions: role.permission_keys - ["inventory:settings"])
      sign_in manager

      patch bulk_update_admin_inventory_unit_conversions_path, params: {
        conversions: { wrong.id => { base_units_per_unit: "0.001" } }
      }

      expect(wrong.reload.base_units_per_unit.to_d).to eq(430)
    end
  end
end
