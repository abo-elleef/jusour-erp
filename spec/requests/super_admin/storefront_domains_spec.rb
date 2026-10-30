# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SuperAdmin storefront domain", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let!(:super_admin) do
    SuperAdminUser.create!(name: "Root", email: "root@example.com",
      password: "password123", password_confirmation: "password123")
  end

  before { sign_in(super_admin, scope: :super_admin_user) }

  it "connects a custom domain to the company's storefront, creating the row if needed" do
    get edit_super_admin_company_storefront_domain_path(company)
    expect(response).to have_http_status(:ok)

    patch super_admin_company_storefront_domain_path(company),
      params: { storefront: { custom_domain: "https://WWW.Curelix.com/" } }

    expect(response).to redirect_to(super_admin_company_path(company))
    storefront = Storefront.unscoped_by_company.find_by!(company_id: company.id)
    expect(storefront.custom_domain).to eq("www.curelix.com")
    expect(storefront.enabled).to be(false)

    get super_admin_company_path(company)
    expect(response.body).to include("https://www.curelix.com")
  end

  it "re-renders with the error for a bad domain" do
    patch super_admin_company_storefront_domain_path(company), params: { storefront: { custom_domain: "localhost" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(Storefront.unscoped_by_company.where(company_id: company.id)).to be_empty
  end

  it "is not reachable by company users" do
    sign_out(:super_admin_user)
    get edit_super_admin_company_storefront_domain_path(company)

    expect(response).not_to have_http_status(:ok)
  end
end
