# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Feature gating by business profile", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: business_type) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  context "distribution company (manufacturing & attendance OFF)" do
    let(:business_type) { "distribution" }

    it "blocks the manufacturing module by direct URL" do
      get admin_inventory_manufacturing_templates_path
      expect(response).to redirect_to(admin_root_path)
    end

    it "blocks the attendance module by direct URL" do
      get admin_accounting_attendance_path
      expect(response).to redirect_to(admin_root_path)
    end

    it "hides the manufacturing tab from the inventory nav" do
      get admin_inventory_suppliers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(admin_inventory_manufacturing_templates_path)
    end
  end

  context "restaurant company (everything on)" do
    let(:business_type) { "restaurant" }

    it "allows the manufacturing module" do
      get admin_inventory_manufacturing_templates_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the manufacturing tab in the inventory nav" do
      get admin_inventory_suppliers_path
      expect(response.body).to include(admin_inventory_manufacturing_templates_path)
    end
  end
end
