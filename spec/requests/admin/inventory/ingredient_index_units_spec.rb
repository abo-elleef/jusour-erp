# frozen_string_literal: true

require "rails_helper"

# The list carries each ingredient's alternate units and their rates, so the
# conversions can be read across the catalog without opening every ingredient.
RSpec.describe "Alternate units on the ingredients list", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }

  before { Current.company = company }

  let!(:oil) do
    ingredient = create(:ingredient, company: company, ingredient_category: category, name: "Oil", unit: "ml")
    ingredient.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, purchase_unit: true, company: company)
    ingredient
  end

  before { sign_in owner }

  it "lists the alternate unit and its rate next to the base unit" do
    get admin_inventory_ingredients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("3785")
    expect(response.body).to include(Ingredient.unit_display_label("gallons"))
    expect(response.body).to include(I18n.t("inventory.ingredients.show.units.purchase"))
  end

  it "says nothing about the review while every rate adds up" do
    get admin_inventory_ingredients_path

    expect(response.body).not_to include(I18n.t("inventory.ingredients.index.conversion_checks_action"))
  end

  describe "when a rate disagrees with the units it converts between" do
    let!(:mushrooms) do
      ingredient = create(:ingredient, company: company, ingredient_category: category, name: "Mushrooms", unit: "kg")
      ingredient.ingredient_units.create!(unit: "g", base_units_per_unit: 430, company: company)
      ingredient
    end

    it "points at the review, filtered to the rates that need one" do
      get admin_inventory_ingredients_path

      expect(response.body).to include(I18n.t("inventory.ingredients.index.conversion_checks", count: 1))
      expect(response.body).to include(admin_inventory_unit_conversions_path(flag: "check"))
    end

    it "counts the inactive ones too when the list is showing them" do
      mushrooms.update!(active: false)

      get admin_inventory_ingredients_path
      expect(response.body).not_to include(I18n.t("inventory.ingredients.index.conversion_checks_action"))

      get admin_inventory_ingredients_path(status: "all")
      expect(response.body).to include(I18n.t("inventory.ingredients.index.conversion_checks", count: 1))
    end
  end

  it "loads the units for the whole page rather than per row" do
    Array.new(3) do |i|
      other = create(:ingredient, company: company, ingredient_category: category, name: "Spice #{i}", unit: "kg")
      other.ingredient_units.create!(unit: "g", base_units_per_unit: 0.001, company: company)
    end

    queries = Hash.new { |h, k| h[k] = [] }
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql]
      queries[:conversions] << sql if sql.include?("ingredient_units")
      queries[:units] << sql if sql.match?(/FROM "units"/)
    end
    get admin_inventory_ingredients_path
    ActiveSupport::Notifications.unsubscribe(subscriber)

    # One load for the rows on the page, one for the review behind the banner.
    expect(queries[:conversions].size).to eq(2)
    # The units they convert to are preloaded, not fetched one conversion at a time.
    expect(queries[:units].size).to be <= 4
  end
end
