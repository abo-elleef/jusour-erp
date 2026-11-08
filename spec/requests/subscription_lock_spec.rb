# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Subscription lock", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "lets an active company through" do
    get edit_account_password_path
    expect(response).to have_http_status(:ok)
  end

  it "shows a renewal banner during the warning window" do
    company.update!(paid_until: Date.current + 3)
    get admin_root_path
    expect(response.body).to include(I18n.t("subscription.banner.expiring", count: 3, date: I18n.l(company.paid_until, format: :long)))
  end

  it "redirects a suspended company to the locked page" do
    company.update!(active: false)
    get edit_account_password_path
    expect(response).to redirect_to(subscription_locked_path)

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("subscription.locked.title"))
  end

  it "locks a company past its grace period but not within it" do
    company.update!(paid_until: Date.current - Company::SUBSCRIPTION_GRACE_DAYS)
    get edit_account_password_path
    expect(response).to have_http_status(:ok)

    company.update!(paid_until: Date.current - Company::SUBSCRIPTION_GRACE_DAYS - 1)
    get edit_account_password_path
    expect(response).to redirect_to(subscription_locked_path)
  end

  it "sends the locked page back to the app once renewed" do
    company.update!(paid_until: Date.current + 30)
    get subscription_locked_path
    expect(response).to redirect_to(root_path)
  end

  it "answers non-HTML requests of a locked company with 402" do
    company.update!(active: false)
    get edit_account_password_path, as: :json
    expect(response).to have_http_status(:payment_required)
  end

  it "still lets a locked user sign out" do
    company.update!(active: false)
    delete destroy_user_session_path
    expect(response).to redirect_to(%r{/})
    expect(response).not_to redirect_to(subscription_locked_path)
  end
end

RSpec.describe "Super admin subscription controls", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, paid_until: Date.current - 30) }
  let!(:super_admin) do
    SuperAdminUser.create!(name: "Root", email: "root@example.com",
      password: "password123", password_confirmation: "password123")
  end

  before { sign_in(super_admin, scope: :super_admin_user) }

  it "records a payment" do
    post extend_subscription_super_admin_company_path(company, months: 12)
    expect(company.reload.paid_until).to eq(Date.current >> 12)
  end

  it "rejects an unsupported period" do
    post extend_subscription_super_admin_company_path(company, months: 5)
    expect(company.reload.paid_until).to eq(Date.current - 30)
  end

  it "lists the company with its status on the dashboard" do
    company # created lazily; it must exist before the dashboard renders
    get super_admin_root_path
    expect(response.body).to include("Expired")
  end

  it "lets the super admin impersonate a locked company's owner" do
    owner = create(:user, :owner, company: company)
    company.update!(active: false)

    get impersonate_super_admin_company_path(company)
    expect(response).to redirect_to(admin_root_path)

    get admin_root_path
    expect(response).to have_http_status(:ok)
    expect(owner.company).to eq(company)
  end
end
