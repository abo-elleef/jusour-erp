# frozen_string_literal: true

require "rails_helper"

# Every grouped view must order categories by their configured position, not the
# alphabet. Names here are chosen so the two orders DISAGREE — "Zebra" sits at
# position 1 and "Apple" at position 3, so an alphabetical fallback is visible.
RSpec.describe "Ingredient category ordering in grouped views", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:kitchen) { create(:location, :central_kitchen, company: company, name: "Central Kitchen") }
  let(:branch) { create(:location, company: company, name: "Branch A") }

  let!(:zebra) { IngredientCategory.create!(name: "Zebra", position: 1, company: company) }
  let!(:middle) { IngredientCategory.create!(name: "Middle", position: 2, company: company) }
  let!(:apple) { IngredientCategory.create!(name: "Apple", position: 3, company: company) }

  def ingredient(name, category)
    Ingredient.create!(name: name, ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 5, company: company)
  end

  def order_of(body, *names)
    names.map { |n| [n, body.index(">#{n}<") || body.index(n)] }
         .sort_by { |(_, i)| i || Float::INFINITY }.map(&:first)
  end

  before { sign_in owner }

  describe "IngredientCategory.grouping_sort_key" do
    it "ranks by position, not name" do
      sorted = [apple, zebra, middle].sort_by { |c| IngredientCategory.grouping_sort_key(c) }
      expect(sorted.map(&:name)).to eq(%w[Zebra Middle Apple])
    end

    it "sorts an absent category last" do
      sorted = [nil, apple, zebra].sort_by { |c| IngredientCategory.grouping_sort_key(c) }
      expect(sorted).to eq([zebra, apple, nil])
    end

    it "falls back to name only when positions tie" do
      a = IngredientCategory.create!(name: "Beta", position: 9, company: company)
      b = IngredientCategory.create!(name: "Alpha", position: 9, company: company)
      sorted = [a, b].sort_by { |c| IngredientCategory.grouping_sort_key(c) }
      expect(sorted.map(&:name)).to eq(%w[Alpha Beta])
    end
  end

  describe "valuation report" do
    it "groups by position, not alphabetically" do
      ingredient("In Zebra", zebra)
      ingredient("In Middle", middle)
      ingredient("In Apple", apple)

      get admin_inventory_reports_valuation_path

      expect(order_of(response.body, "Zebra", "Middle", "Apple")).to eq(%w[Zebra Middle Apple])
    end
  end

  describe "vendor count sheet" do
    it "groups by position, not alphabetically" do
      supplier = Supplier.create!(name: "Fresh Farms", company: company)
      [[zebra, "In Zebra"], [middle, "In Middle"], [apple, "In Apple"]].each do |cat, name|
        ing = ingredient(name, cat)
        SupplierIngredient.create!(supplier: supplier, ingredient: ing)
        kitchen.ingredient_locations.create!(ingredient: ing, quantity_on_hand: 3, reorder_threshold: 1)
      end

      get count_sheet_admin_inventory_supplier_path(supplier, location_id: kitchen.id)

      expect(order_of(response.body, "Zebra", "Middle", "Apple")).to eq(%w[Zebra Middle Apple])
    end
  end

  describe "stock transfer progress summary" do
    it "groups by position, not alphabetically" do
      transfer = create(:stock_transfer, company: company, from_location: kitchen,
        to_location: branch, requested_by: owner)
      [[zebra, "In Zebra"], [middle, "In Middle"], [apple, "In Apple"]].each_with_index do |(cat, name), i|
        create(:stock_transfer_line, stock_transfer: transfer,
          ingredient: ingredient(name, cat), quantity_requested: 2, position: i)
      end

      get admin_inventory_stock_transfer_path(transfer)

      expect(order_of(response.body, "Zebra", "Middle", "Apple")).to eq(%w[Zebra Middle Apple])
    end
  end

  describe "stock take" do
    it "sorts the category column by position, not alphabetically" do
      take = StockTake.create!(company: company, user: owner, location: kitchen, status: "in_progress")
      [[zebra, "In Zebra"], [middle, "In Middle"], [apple, "In Apple"]].each do |cat, name|
        take.stock_take_items.create!(ingredient: ingredient(name, cat), expected_quantity: 4)
      end

      get admin_inventory_stock_take_path(take, sort: "category")

      expect(order_of(response.body, "In Zebra", "In Middle", "In Apple"))
        .to eq(["In Zebra", "In Middle", "In Apple"])
    end
  end
end
