# frozen_string_literal: true

require "rails_helper"

# Once an ingredient is scoped to specific locations (see
# ingredient_location_scoping_spec.rb), that restriction has to actually mean
# something: the manual stock-adjustment location dropdown, and the ingredient
# picker on a stock transfer, both need to stop offering a location/ingredient
# combination that isn't allowed. Stock takes are covered separately in
# stock_takes_spec.rb.
RSpec.describe "Ingredient location restrictions apply to stock movement", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:branch_a) { create(:location, company: company, name: "Branch A") }
  let!(:branch_b) { create(:location, company: company, name: "Branch B") }

  before { sign_in owner }

  describe "stock adjustment" do
    let!(:ingredient) do
      Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
        reorder_threshold: 1, company: company, all_locations: false, restricted_location_ids: [branch_a.id])
    end

    it "only offers the ingredient's allowed locations in the adjust dropdown" do
      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).to include(branch_a.name)
      expect(response.body).not_to include(branch_b.name)
    end

    it "allows an adjustment at an allowed location" do
      post adjust_admin_inventory_ingredient_path(ingredient), params: {
        location_id: branch_a.id, quantity_delta: "5", unit: "kg",
        adjustment_type: StockAdjustment::ADJUSTMENT_TYPES.first, reason_notes: "recount"
      }

      expect(response).to redirect_to(admin_inventory_ingredient_path(ingredient))
      expect(flash[:alert]).to be_nil
    end

    it "rejects an adjustment at a location the ingredient isn't scoped to" do
      expect {
        post adjust_admin_inventory_ingredient_path(ingredient), params: {
          location_id: branch_b.id, quantity_delta: "5", unit: "kg",
          adjustment_type: StockAdjustment::ADJUSTMENT_TYPES.first, reason_notes: "recount"
        }
      }.not_to change(StockAdjustment, :count)

      expect(flash[:alert]).to be_present
    end
  end

  describe "stock stranded outside allowed locations" do
    let!(:ingredient) do
      Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
        reorder_threshold: 1, company: company, all_locations: false, restricted_location_ids: [branch_a.id])
    end

    it "flags a nonzero balance left at a location the ingredient isn't allowed at" do
      create(:ingredient_location, ingredient: ingredient, location: branch_b, quantity_on_hand: 6.0)

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).to include(I18n.t("inventory.ingredients.show.disallowed_stock.title"))
      expect(response.body).to include(branch_b.name)
    end

    it "does not flag a zero balance at a disallowed location" do
      create(:ingredient_location, ingredient: ingredient, location: branch_b, quantity_on_hand: 0)

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).not_to include(I18n.t("inventory.ingredients.show.disallowed_stock.title"))
    end

    it "does not flag a balance at an allowed location" do
      create(:ingredient_location, ingredient: ingredient, location: branch_a, quantity_on_hand: 6.0)

      get admin_inventory_ingredient_path(ingredient)

      expect(response.body).not_to include(I18n.t("inventory.ingredients.show.disallowed_stock.title"))
    end
  end

  describe "stock transfers" do
    let!(:restricted) do
      Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
        reorder_threshold: 1, company: company, all_locations: false, restricted_location_ids: [branch_a.id])
    end
    let!(:everywhere) do
      Ingredient.create!(name: "Salt", ingredient_category: category, unit: "kg",
        reorder_threshold: 1, company: company)
    end

    it "excludes an ingredient from the picker once both locations are chosen and it isn't allowed at one of them" do
      get new_admin_inventory_stock_transfer_path(from_location_id: branch_a.id, to_location_id: branch_b.id)

      expect(response.body).to include(everywhere.name)
      expect(response.body).not_to include(restricted.name)
    end

    it "keeps the full catalog when no locations are chosen yet" do
      get new_admin_inventory_stock_transfer_path

      expect(response.body).to include(everywhere.name)
      expect(response.body).to include(restricted.name)
    end

    it "blocks saving a line for an ingredient not allowed at one of the transfer's locations" do
      params = {
        stock_transfer: {
          from_location_id: branch_a.id, to_location_id: branch_b.id, transferred_on: Date.current,
          stock_transfer_lines_attributes: {
            "0" => { ingredient_id: restricted.id, unit: "kg", quantity_requested_input: "1" }
          }
        }
      }

      expect {
        post admin_inventory_stock_transfers_path, params: params
      }.not_to change(StockTransfer, :count)
    end

    it "allows saving a line for an all_locations ingredient between any two locations" do
      params = {
        stock_transfer: {
          from_location_id: branch_a.id, to_location_id: branch_b.id, transferred_on: Date.current,
          stock_transfer_lines_attributes: {
            "0" => { ingredient_id: everywhere.id, unit: "kg", quantity_requested_input: "1" }
          }
        }
      }

      expect {
        post admin_inventory_stock_transfers_path, params: params
      }.to change(StockTransfer, :count).by(1)
    end
  end
end
