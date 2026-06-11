# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Locations::Ingredients", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  let!(:location) { create(:location, company: company, name: "Westside Branch") }
  let!(:ingredient) { create(:ingredient, company: company, quantity_on_hand: 10.0) }

  describe "GET /admin/locations/:location_id/ingredients" do
    it "shows per-location stock levels" do
      create(:ingredient_location, location: location, ingredient: ingredient, quantity_on_hand: 3.0)

      get admin_location_ingredients_path(location)

      expect(response).to have_http_status(:ok)
    end

    it "filters by low stock" do
      create(:ingredient_location, location: location, ingredient: ingredient,
        quantity_on_hand: 0.5, reorder_threshold: 2.0)

      get admin_location_ingredients_path(location), params: { stock: "low" }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/locations/:location_id/ingredients" do
    it "assigns an ingredient to the location" do
      expect {
        post admin_location_ingredients_path(location), params: { ingredient_id: ingredient.id }
      }.to change(IngredientLocation, :count).by(1)

      il = IngredientLocation.last
      expect(il.location).to eq(location)
      expect(il.ingredient).to eq(ingredient)
      expect(il.quantity_on_hand.to_f).to eq(0.0)
      expect(il.reorder_threshold).to eq(ingredient.reorder_threshold)
      expect(response).to redirect_to(admin_location_ingredients_path(location))
    end
  end

  describe "PATCH /admin/locations/:location_id/ingredients/:id" do
    it "updates the reorder threshold for this location" do
      il = create(:ingredient_location, location: location, ingredient: ingredient, reorder_threshold: 2.0)

      patch admin_location_ingredient_path(location, ingredient), params: {
        ingredient_location: { reorder_threshold: "5.5" }
      }

      expect(il.reload.reorder_threshold.to_f).to eq(5.5)
      expect(response).to redirect_to(admin_location_ingredients_path(location))
    end
  end

  describe "DELETE /admin/locations/:location_id/ingredients/:id" do
    it "removes the ingredient from the location" do
      create(:ingredient_location, location: location, ingredient: ingredient)

      expect {
        delete admin_location_ingredient_path(location, ingredient)
      }.to change(IngredientLocation, :count).by(-1)

      expect(response).to redirect_to(admin_location_ingredients_path(location))
    end
  end

  describe "POST /admin/locations/:location_id/ingredients/:ingredient_id/adjust" do
    it "creates a stock adjustment scoped to the location" do
      expect {
        post adjust_admin_location_ingredient_path(location, ingredient), params: {
          quantity_delta: "5.0",
          adjustment_type: "manual_add",
          reason_notes: "Delivery received"
        }
      }.to change(StockAdjustment, :count).by(1)

      adjustment = StockAdjustment.last
      expect(adjustment.location).to eq(location)
      expect(adjustment.quantity_delta).to eq(5.0)
    end

    it "updates the per-location quantity" do
      create(:ingredient_location, location: location, ingredient: ingredient, quantity_on_hand: 3.0)

      post adjust_admin_location_ingredient_path(location, ingredient), params: {
        quantity_delta: "2.0",
        adjustment_type: "manual_add"
      }

      il = IngredientLocation.find_by(location: location, ingredient: ingredient)
      expect(il.quantity_on_hand.to_f).to eq(5.0)
    end

    it "also updates the global ingredient quantity" do
      original_qty = ingredient.quantity_on_hand

      post adjust_admin_location_ingredient_path(location, ingredient), params: {
        quantity_delta: "4.0",
        adjustment_type: "delivery"
      }

      expect(ingredient.reload.quantity_on_hand.to_f).to eq(original_qty.to_f + 4.0)
    end
  end
end
