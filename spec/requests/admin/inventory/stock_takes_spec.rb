# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Inventory::StockTakes", type: :request do
  include Devise::Test::IntegrationHelpers

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

    it "blocks a second in-progress count for the same location" do
      create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 1.0)
      StockTake.create!(company: company, user: owner, location: kitchen, status: "in_progress", started_at: Time.current)

      expect {
        post admin_inventory_stock_takes_path, params: { location_id: kitchen.id }
      }.not_to change(StockTake, :count)
      expect(flash[:alert]).to be_present
    end
  end

  describe "POST complete" do
    it "applies the variance to the location (updates on-hand and the batch ledger)" do
      create(:ingredient_location, location: kitchen, ingredient: ingredient, quantity_on_hand: 0.0)
      take = StockTake.create!(company: company, user: owner, location: kitchen, status: "in_progress", started_at: Time.current)
      item = take.stock_take_items.create!(ingredient: ingredient, expected_quantity: 0)
      item.update!(counted_quantity: 9)
      item.calculate_variance!
      item.save!

      post complete_admin_inventory_stock_take_path(take)

      adjustment = ingredient.stock_adjustments.where(adjustment_type: "cycle_count_correction").last
      expect(adjustment.location).to eq(kitchen)
      expect(kitchen.ingredient_stock(ingredient).quantity_on_hand.to_d).to eq(9)
      expect(ingredient.stock_batches.where(location: kitchen).sum(:quantity_remaining)).to eq(9)
    end
  end
end
