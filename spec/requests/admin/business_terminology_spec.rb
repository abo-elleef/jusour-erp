# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Business-type terminology", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:owner) { create(:user, :owner, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Widget") }

  before do
    Current.company = company
    sign_in owner
  end

  context "distribution company" do
    let(:company) { create(:company, business_type: "distribution", locale: "en") }

    it "relabels the ingredients index headline + button to 'Product' vocabulary" do
      get admin_inventory_ingredients_path(locale: "en")
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(%r{<h1[^>]*>\s*Products\s*</h1>})
      expect(response.body).to include("New product")
    end
  end

  context "restaurant company" do
    let(:company) { create(:company, business_type: "restaurant", locale: "en") }

    it "keeps the 'Ingredients' headline" do
      get admin_inventory_ingredients_path(locale: "en")
      expect(response.body).to match(%r{<h1[^>]*>\s*Ingredients\s*</h1>})
    end
  end
end
