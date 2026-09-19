# frozen_string_literal: true

require "rails_helper"

# The manufacturing (production) tab sits behind its own key rather than the
# inventory:view section gate, so roles that read inventory — sub-managers — do
# not automatically get to define recipes or record production.
RSpec.describe "Who can reach the manufacturing tab", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "restaurant") }

  before { Current.company = company }

  def visit_all
    [
      admin_inventory_manufacturing_templates_path,
      admin_inventory_manufacturing_runs_path
    ].map { |path| get(path); response.status }
  end

  %w[owner super_manager manager accountant].each do |role|
    it "lets a #{role} in" do
      sign_in create(:user, company: company, role: role)

      expect(visit_all).to all(eq(200))
    end
  end

  %w[sub_manager cashier kitchen].each do |role|
    it "keeps a #{role} out" do
      sign_in create(:user, company: company, role: role)

      expect(visit_all).not_to include(200)
    end
  end

  it "hides the tab from a sub-manager's inventory nav" do
    sign_in create(:user, company: company, role: "sub_manager")

    get admin_inventory_ingredients_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(admin_inventory_manufacturing_templates_path)
  end

  it "still shows it to a manager" do
    sign_in create(:user, company: company, role: "manager")

    get admin_inventory_ingredients_path
    expect(response.body).to include(admin_inventory_manufacturing_templates_path)
  end
end
