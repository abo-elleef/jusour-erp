# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingredient cost labelling", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let!(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 750, quantity_on_hand: 10, company: company)
  end

  before { sign_in owner }

  it "does not claim the cost is a weighted average — nothing averages it" do
    get admin_inventory_ingredient_path(ingredient)

    expect(response.body).to include(I18n.t("inventory.ingredients.show.cost_hint"))
    expect(I18n.t("inventory.ingredients.show.cost_hint", locale: :en)).not_to match(/weighted/i)
    expect(I18n.t("inventory.ingredients.show.cost_hint", locale: :ar)).not_to include("المرجح")
  end

  it "states the real currency on the form rather than dollars" do
    get edit_admin_inventory_ingredient_path(ingredient)

    expect(response.body).to include(ApplicationHelper::MONEY_SYMBOL)
    expect(I18n.t("inventory.ingredients.form.stock_cost_hint", locale: :en, currency: "X", unit: "kg"))
      .not_to match(/dollar/i)
  end
end
