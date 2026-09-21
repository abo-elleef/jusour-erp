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

  it "loads the units for the whole page rather than per row" do
    Array.new(3) do |i|
      other = create(:ingredient, company: company, ingredient_category: category, name: "Spice #{i}", unit: "kg")
      other.ingredient_units.create!(unit: "g", base_units_per_unit: 0.001, company: company)
    end

    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries << payload[:sql] if payload[:sql].include?("ingredient_units")
    end
    get admin_inventory_ingredients_path
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(queries.size).to eq(1)
  end
end
