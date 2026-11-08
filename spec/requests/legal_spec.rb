# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legal pages and support links", type: :request do
  include Devise::Test::IntegrationHelpers

  around do |example|
    original = ENV["SUPPORT_WHATSAPP"]
    ENV["SUPPORT_WHATSAPP"] = "201130303780"
    example.run
  ensure
    ENV["SUPPORT_WHATSAPP"] = original
  end

  it "serves the terms to a signed-out visitor, in English" do
    get terms_path(locale: :en)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Terms of service")
    expect(response.body).to include("grace period of #{Company::SUBSCRIPTION_GRACE_DAYS} days")
  end

  it "serves the terms in Arabic with right-to-left direction" do
    get terms_path(locale: :ar)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("شروط الخدمة")
    expect(response.body).to include('dir="rtl"')
  end

  it "links terms and WhatsApp support from the sign-in page" do
    get new_user_session_path
    expect(response.body).to include(terms_path)
    expect(response.body).to include("https://wa.me/201130303780")
  end

  it "omits the WhatsApp link when no number is configured" do
    ENV["SUPPORT_WHATSAPP"] = nil
    get terms_path
    expect(response.body).not_to include("wa.me")
  end

  it "shows the links in the admin sidebar" do
    company = create(:company)
    Current.company = company
    sign_in create(:user, :owner, company: company)

    get admin_root_path
    expect(response.body).to include(terms_path)
    expect(response.body).to include("https://wa.me/201130303780")
  end

  it "keeps the terms readable for a locked company" do
    company = create(:company, active: false)
    Current.company = company
    sign_in create(:user, :owner, company: company)

    get terms_path
    expect(response).to have_http_status(:ok)
  end
end
