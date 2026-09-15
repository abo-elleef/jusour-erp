# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deriving a manufactured ingredient's cost from its batches", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:location) { create(:location, :central_kitchen, company: company) }
  let(:category) { IngredientCategory.create!(name: "Prep", position: 1, company: company) }

  let!(:flour) do
    Ingredient.create!(name: "Flour", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 80, quantity_on_hand: 100, company: company)
  end

  let!(:dough) do
    Ingredient.create!(name: "Dough", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 0, cost_source: "derived",
      quantity_on_hand: 0, company: company)
  end

  let!(:template) do
    template = ManufacturingTemplate.create!(name: "Make Dough", output_ingredient: dough,
      yield_quantity: 5, active: false, company: company)
    ManufacturingTemplateLine.create!(manufacturing_template: template, ingredient: flour, quantity_used: 4)
    template.update!(active: true)
    template
  end

  before { sign_in owner }

  def stock_dough(qty:, cost:)
    StockBatch.create!(ingredient: dough, location: location, quantity_received: qty,
      quantity_remaining: qty, cost_per_unit_cents: cost, received_on: Date.current)
  end

  describe "the ingredient page" do
    it "says the cost is derived, and offers a refresh once there are batches" do
      stock_dough(qty: 4, cost: 250)

      get admin_inventory_ingredient_path(dough)

      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.derived_badge"))
      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.action_refresh"))
    end

    it "explains itself rather than offering a refresh when no stock is left" do
      get admin_inventory_ingredient_path(dough)

      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.no_batches_hint"))
      expect(response.body).not_to include(I18n.t("inventory.ingredients.cost_derive.action_refresh"))
    end

    it "shows a hand-kept cost against what the batches say, behind a confirm" do
      dough.update!(cost_source: "manual", cost_per_unit_cents: 3000)
      stock_dough(qty: 10, cost: 570)

      get admin_inventory_ingredient_path(dough)

      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.manual_badge"))
      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.action_switch"))
      expect(response.body).to include("data-turbo-confirm")
    end

    it "offers nothing on a purchased ingredient" do
      get admin_inventory_ingredient_path(flour)

      expect(response.body).not_to include(I18n.t("inventory.ingredients.cost_derive.action_switch"))
      expect(response.body).not_to include(I18n.t("inventory.ingredients.cost_derive.derived_badge"))
    end
  end

  describe "switching a hand-kept cost over" do
    it "takes the batch average and hands the cost to the sync" do
      dough.update!(cost_source: "manual", cost_per_unit_cents: 3000)
      stock_dough(qty: 10, cost: 570)

      post sync_cost_from_batches_admin_inventory_ingredient_path(dough)

      expect(dough.reload.cost_per_unit_cents).to eq(570)
      expect(dough.cost_source).to eq("derived")
      follow_redirect!
      money = ApplicationController.helpers
      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.applied",
        from: money.format_money(3000), to: money.format_money(570)))
    end

    it "keeps the current cost when there is no stock to average" do
      dough.update!(cost_source: "manual", cost_per_unit_cents: 3000)

      post sync_cost_from_batches_admin_inventory_ingredient_path(dough)

      expect(dough.reload.cost_per_unit_cents).to eq(3000)
    end

    it "refuses on an ingredient no template produces" do
      post sync_cost_from_batches_admin_inventory_ingredient_path(flour)

      expect(flour.reload.cost_source).to eq("manual")
      follow_redirect!
      expect(response.body).to include(I18n.t("inventory.ingredients.cost_derive.not_manufactured"))
    end
  end

  describe "editing the cost by hand" do
    it "takes the number back so the nightly sync stops overwriting it" do
      stock_dough(qty: 4, cost: 250)
      post sync_cost_from_batches_admin_inventory_ingredient_path(dough)
      expect(dough.reload.cost_source).to eq("derived")

      patch admin_inventory_ingredient_path(dough), params: {
        ingredient: { cost_per_unit_dollars: "9.99" }
      }

      expect(dough.reload.cost_per_unit_cents).to eq(999)
      expect(dough.cost_source).to eq("manual")
    end

    it "leaves a derived cost derived when an unrelated edit resubmits the same figure" do
      stock_dough(qty: 4, cost: 250)
      post sync_cost_from_batches_admin_inventory_ingredient_path(dough)

      patch admin_inventory_ingredient_path(dough), params: {
        ingredient: { name: "Dough (renamed)", cost_per_unit_dollars: "2.50" }
      }

      expect(dough.reload.name).to eq("Dough (renamed)")
      expect(dough.cost_source).to eq("derived")
    end
  end
end
