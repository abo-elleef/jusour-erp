# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SuperAdmin company feature control", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "restaurant") }
  let!(:super_admin) do
    SuperAdminUser.create!(name: "Root", email: "root@example.com",
      password: "password123", password_confirmation: "password123")
  end

  before { sign_in(super_admin, scope: :super_admin_user) }

  it "sets business type and per-feature overrides from the edit form" do
    patch super_admin_company_path(company), params: {
      company: { name: company.name, slug: company.slug, timezone: company.timezone,
                 currency: company.currency, locale: company.locale, active: "1",
                 business_type: "distribution" },
      feature_overrides: { "ar_credit_sales" => "off", "manufacturing" => "on", "attendance" => "inherit" }
    }

    company.reload
    expect(company.business_type).to eq("distribution")
    # Explicit overrides win over the distribution defaults.
    expect(company.feature_enabled?(:ar_credit_sales)).to be(false) # forced off
    expect(company.feature_enabled?(:manufacturing)).to be(true)    # forced on
    # "inherit" stores no key, so the distribution default (attendance off) applies.
    expect(company.feature_overrides).not_to have_key("attendance")
    expect(company.feature_enabled?(:attendance)).to be(false)
  end

  it "clears an override back to inherit" do
    company.update!(feature_overrides: { "ar_credit_sales" => true })

    patch super_admin_company_path(company), params: {
      company: { name: company.name, slug: company.slug, timezone: company.timezone,
                 currency: company.currency, locale: company.locale, active: "1",
                 business_type: "restaurant" },
      feature_overrides: { "ar_credit_sales" => "inherit" }
    }

    expect(company.reload.feature_overrides).not_to have_key("ar_credit_sales")
    expect(company.feature_enabled?(:ar_credit_sales)).to be(false) # restaurant default
  end

  it "renders the edit form with the feature panel" do
    get edit_super_admin_company_path(company)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Feature overrides")
    expect(response.body).to include("feature_overrides[ar_credit_sales]")
  end
end
