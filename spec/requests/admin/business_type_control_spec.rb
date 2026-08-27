# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Business type is not tenant-controllable", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "restaurant") }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "ignores a business_type param on the tenant settings update" do
    patch admin_settings_path, params: { business_type: "distribution" }
    expect(company.reload.business_type).to eq("restaurant")
  end

  it "no longer renders a business-profile control on the settings page" do
    get admin_settings_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("business_type")
  end
end
