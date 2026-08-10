# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::StockTakes", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, quantity_on_hand: 0) }

  before do
    Current.company = company
    sign_in owner
  end

  describe "POST create" do
    it "requires a location" do
      expect {
        post admin_inventory_stock_takes_path, params: { notes: "x" }
      }.not_to change(StockTake, :count)
      expect(flash[:alert]).to be_present
    end

    it "seeds items from the location's stock with per-location expected quantities" do
      create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 12.0)
      # An ingredient stocked only at the branch must not appear in a kitchen count.
      other = create(:ingredient, company: company, ingredient_category: category)
      create(:ingredient_location, location: branch, ingredient: other, quantity_on_hand: 5.0)

      post admin_inventory_stock_takes_path, params: { location_id: kitchen.id }

      take = StockTake.last
      expect(take.location).to eq(kitchen)
      expect(take.stock_take_items.map(&:ingredient)).to eq([ingredient])
      expect(take.stock_take_items.first.expected_quantity.to_d).to eq(12.0)
    end

    it "optionally limits items to ingredients linked to the chosen vendor" do
      supplier = Supplier.create!(company: company, name: "Metro Foods")
      other_supplier = Supplier.create!(company: company, name: "Other Vendor")
      linked = create(:ingredient, company: company, ingredient_category: category, name: "Linked")
      unlinked = create(:ingredient, company: company, ingredient_category: category, name: "Unlinked")
      create(:ingredient_location, location: kitchen, ingredient: linked, quantity_on_hand: 4.0)
      create(:ingredient_location, location: kitchen, ingredient: unlinked, quantity_on_hand: 7.0)
      SupplierIngredient.create!(supplier: supplier, ingredient: linked, price_cents: 100)
      SupplierIngredient.create!(supplier: other_supplier, ingredient: unlinked, price_cents: 100)

      post admin_inventory_stock_takes_path, params: { location_id: kitchen.id, supplier_id: supplier.id }

      take = StockTake.last
      expect(take.supplier).to eq(supplier)
      expect(take.stock_take_items.map(&:ingredient)).to eq([linked])
      expect(take.stock_take_items.first.expected_quantity.to_d).to eq(4.0)
    end

    it "blocks a second in-progress count for the same location" do
      create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 1.0)
      StockTake.create!(company: company, user: owner, location: kitchen, status: "in_progress", started_at: Time.current)

      expect {
        post admin_inventory_stock_takes_path, params: { location_id: kitchen.id }
      }.not_to change(StockTake, :count)
      expect(flash[:alert]).to be_present
    end

    it "blocks a new count while the location has a completing take" do
      create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 1.0)
      StockTake.create!(company: company, user: owner, location: kitchen, status: "completing", started_at: Time.current)

      expect {
        post admin_inventory_stock_takes_path, params: { location_id: kitchen.id }
      }.not_to change(StockTake, :count)
      expect(flash[:alert]).to be_present
    end
  end

  describe "PATCH update" do
    it "saves a count entered in an alternate unit and converts variance to the base unit" do
      oil = create(:ingredient, company: company, ingredient_category: category, unit: "ml",
        quantity_on_hand: 0, cost_per_unit_cents: 2, reorder_threshold: 1)
      oil.ingredient_units.create!(unit: "liters", base_units_per_unit: 1000, company: company)
      create(:ingredient_location, location: kitchen, ingredient: oil, quantity_on_hand: 1000.0)

      take = StockTake.create!(company: company, user: owner, location: kitchen, status: "in_progress", started_at: Time.current)
      item = take.stock_take_items.create!(ingredient: oil, expected_quantity: 1000)

      patch admin_inventory_stock_take_path(take), params: {
        stock_take_items: {
          item.id => { counted_quantity: "1.2", counted_unit: "liters" }
        }
      }

      item.reload
      expect(item.counted_quantity.to_d).to eq(1.2)
      expect(item.counted_unit).to eq("liters")
      expect(item.variance.to_d).to eq(200)
    end
  end

  describe "POST complete" do
    def build_take_with_variance
      create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 0.0)
      take = StockTake.create!(company: company, user: owner, location: kitchen, status: "in_progress", started_at: Time.current)
      item = take.stock_take_items.create!(ingredient: ingredient, expected_quantity: 0)
      item.update!(counted_quantity: 9)
      item.calculate_variance!
      item.save!
      take
    end

    it "enqueues completion and does not apply stock until the job runs" do
      take = build_take_with_variance

      expect {
        post complete_admin_inventory_stock_take_path(take)
      }.to have_enqueued_job(Inventory::CompleteStockTakeJob).with(take.id, owner.id)

      take.reload
      expect(take.status).to eq("completing")
      expect(kitchen.ingredient_stock(ingredient).quantity_on_hand.to_d).to eq(0)
      expect(flash[:notice]).to eq(I18n.t("flash.stock_take.completing"))
    end

    it "applies the variance when the job runs" do
      take = build_take_with_variance

      perform_enqueued_jobs only: Inventory::CompleteStockTakeJob do
        post complete_admin_inventory_stock_take_path(take)
      end

      take.reload
      expect(take.status).to eq("completed")
      expect(take.completed_at).to be_present

      adjustment = ingredient.stock_adjustments.where(adjustment_type: "cycle_count_correction").last
      expect(adjustment.location).to eq(kitchen)
      expect(kitchen.ingredient_stock(ingredient).quantity_on_hand.to_d).to eq(9)
      expect(ingredient.stock_batches.where(location: kitchen).sum(:quantity_remaining)).to eq(9)
    end
  end
end
