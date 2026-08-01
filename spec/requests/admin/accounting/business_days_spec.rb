# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Accounting::BusinessDays", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let!(:branch) { create(:location, company: company, name: "Downtown") }

  describe "GET /admin/accounting/business_days" do
    it "shows the hub for accounting users" do
      sign_in owner
      get admin_accounting_business_days_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Downtown")
      expect(response.body).to include(I18n.t("accounting.business_days.company_defaults"))
    end
  end

  describe "PATCH defaults" do
    it "lets the owner update the company start hour" do
      sign_in owner
      patch update_defaults_admin_accounting_business_days_path, params: { business_day_start_hour: 5 }
      expect(response).to redirect_to(admin_accounting_business_days_path)
      expect(CompanySetting.find_by!(company: company).business_day_start_hour).to eq(5)
    end

    it "denies non-owners" do
      sign_in manager
      patch update_defaults_admin_accounting_business_days_path, params: { business_day_start_hour: 3 }
      expect(response).to have_http_status(:redirect)
      expect(CompanySetting.find_by(company: company)&.business_day_start_hour).not_to eq(3)
    end
  end

  describe "PATCH branch settings" do
    it "lets the owner switch a branch to manual and set a start hour" do
      sign_in owner
      patch admin_accounting_business_day_path(location_id: branch.id), params: {
        business_day_mode: "manual",
        business_day_start_hour: "4"
      }
      expect(response).to redirect_to(admin_accounting_business_days_path)
      branch.reload
      expect(branch.business_day_mode).to eq("manual")
      expect(branch.business_day_start_hour).to eq(4)
      expect(LocationOperatingDay.current_for(branch)).to be_present
    end
  end

  describe "POST advance" do
    before { branch.update!(business_day_mode: "manual") }

    it "advances a clear manual branch" do
      sign_in owner
      LocationOperatingDay.ensure_open!(branch, date: Date.new(2026, 5, 1), user: owner)

      post advance_admin_accounting_business_days_path, params: { location_id: branch.id }
      expect(response).to redirect_to(admin_accounting_business_days_path)
      expect(BusinessDay.today(location: branch)).to eq(Date.new(2026, 5, 2))
    end
  end
end
