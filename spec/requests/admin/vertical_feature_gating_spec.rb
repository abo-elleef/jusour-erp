# frozen_string_literal: true

require "rails_helper"

# D2: each vertical sees the reports and screens that mean something for it.
# A dental distributor has no menu, no tickets and no kitchen; a restaurant has no
# credit sales. The nav hides what doesn't apply and the controllers refuse it, so a
# stale bookmark can't reach a screen that would only ever read empty.
RSpec.describe "Vertical feature gating", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  context "a distribution company" do
    let(:company) { create(:company, business_type: "distribution") }

    it "cannot reach the menu-shaped reports by URL" do
      [admin_accounting_sales_reports_path,
       admin_accounting_food_costs_path,
       admin_accounting_usage_reports_path,
       admin_accounting_tax_reports_path,
       admin_orders_path].each do |path|
        get path
        expect(response).to redirect_to(admin_root_path), "expected #{path} to be gated"
      end
    end

    it "cannot reach the kitchen display" do
      get kitchen_path
      expect(response).to redirect_to(root_path)
    end

    it "hides Orders and Menu from the sidebar, and offers Sales instead" do
      get admin_root_path(locale: "en")

      expect(response.body).not_to include(">#{I18n.t('nav.orders', locale: 'en')}<")
      expect(response.body).not_to include(">#{I18n.t('nav.menu', locale: 'en')}<")
      expect(response.body).to include(admin_sales_customer_invoices_path)
    end

    it "still reaches its own reports" do
      get admin_sales_reports_path
      expect(response).to have_http_status(:ok)
    end
  end

  context "a restaurant company" do
    let(:company) { create(:company, business_type: "restaurant") }

    it "keeps every menu-shaped report" do
      [admin_accounting_sales_reports_path,
       admin_accounting_food_costs_path,
       admin_accounting_usage_reports_path,
       admin_accounting_tax_reports_path,
       admin_orders_path].each do |path|
        get path
        expect(response).to have_http_status(:ok), "expected #{path} to stay available"
      end
    end

    it "shows Orders and Menu in the sidebar" do
      get admin_root_path(locale: "en")

      expect(response.body).to include(">#{I18n.t('nav.orders', locale: 'en')}<")
      expect(response.body).to include(">#{I18n.t('nav.menu', locale: 'en')}<")
    end

    it "has no credit-sales area" do
      get admin_sales_customer_invoices_path
      expect(response).to redirect_to(admin_root_path)
    end
  end

  context "an override" do
    let(:company) { create(:company, business_type: "distribution") }

    it "lets a super admin turn a report back on for one company" do
      company.update!(feature_overrides: { "menu" => true })

      get admin_accounting_sales_reports_path
      expect(response).to have_http_status(:ok)
    end
  end
end
