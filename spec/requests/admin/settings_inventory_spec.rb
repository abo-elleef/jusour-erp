# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin settings inventory", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "defaults to restricting transfers to source stock" do
    expect(Setting.restrict_stock_transfers_to_source?).to be(true)
  end

  it "lets the owner turn restrict mode off" do
    patch admin_settings_path, params: { restrict_stock_transfers_to_source: "0" }

    expect(response).to redirect_to(admin_settings_path)
    expect(CompanySetting.find_by!(company: company).restrict_stock_transfers_to_source).to be(false)
  end

  it "lets the owner turn restrict mode back on" do
    Setting.set("restrict_stock_transfers_to_source", false)

    patch admin_settings_path, params: { restrict_stock_transfers_to_source: "1" }

    expect(CompanySetting.find_by!(company: company).restrict_stock_transfers_to_source).to be(true)
  end

  describe "fractional sales quantities" do
    it "defaults to whole numbers only" do
      expect(Setting.allow_fractional_sales_quantities?).to be(false)
    end

    it "lets the owner allow fractions, and turn them off again" do
      patch admin_settings_path, params: { allow_fractional_sales_quantities: "1" }
      expect(CompanySetting.find_by!(company: company).allow_fractional_sales_quantities).to be(true)

      patch admin_settings_path, params: { allow_fractional_sales_quantities: "0" }
      expect(CompanySetting.find_by!(company: company).allow_fractional_sales_quantities).to be(false)
    end

    it "shows the switch only to companies that sell by invoice" do
      get admin_settings_path
      expect(response.body).not_to include("allow_fractional_sales_quantities")

      company.update!(business_type: "distribution")
      get admin_settings_path
      expect(response.body).to include("allow_fractional_sales_quantities")
    end
  end

  describe "eleven-digit phones" do
    it "is off by default and the owner can turn it on and off" do
      expect(Setting.require_eleven_digit_phones?).to be(false)
      get admin_settings_path
      expect(response.body).to include("require_eleven_digit_phones")

      patch admin_settings_path, params: { require_eleven_digit_phones: "1" }
      expect(CompanySetting.find_by!(company: company).require_eleven_digit_phones).to be(true)

      patch admin_settings_path, params: { require_eleven_digit_phones: "0" }
      expect(CompanySetting.find_by!(company: company).require_eleven_digit_phones).to be(false)
    end
  end

  describe "notification levels" do
    it "shows every kind with its level and saves only the overrides" do
      get admin_settings_path
      section = Nokogiri::HTML(response.body).at("[data-testid=settings-notification-levels]")
      expect(section.at("select[name='notification_levels[low_stock]'] option[selected]")["value"]).to eq("quiet")

      patch admin_settings_path, params: { notification_levels: {
        low_stock: "popup", cash_variance: "alert", bogus: "quiet", price_change: "loud"
      } }

      expect(response).to redirect_to(admin_settings_path)
      expect(CompanySetting.find_by!(company: company).notification_levels).to eq("low_stock" => "popup")
    end
  end
end
