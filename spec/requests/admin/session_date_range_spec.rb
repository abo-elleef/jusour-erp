# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session-based shared date range", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }

  before { sign_in owner }

  def date_field_value(name)
    match = response.body.match(/name="#{name}"[^>]*value="([^"]*)"/) ||
            response.body.match(/value="([^"]*)"[^>]*name="#{name}"/)
    match&.[](1)
  end

  describe "cross-page persistence" do
    it "reuses a range applied on expenses when visiting sales reports without params" do
      get admin_accounting_expenses_path(start_date: "2026-03-01", end_date: "2026-03-15")
      expect(response).to have_http_status(:ok)
      expect(session[:admin_start_date]).to eq("2026-03-01")
      expect(session[:admin_end_date]).to eq("2026-03-15")

      get admin_accounting_sales_reports_path
      expect(response).to have_http_status(:ok)
      expect(date_field_value("start_date")).to eq("2026-03-01")
      expect(date_field_value("end_date")).to eq("2026-03-15")
    end

    it "reuses the session range on inventory variance" do
      get admin_accounting_expenses_path(start_date: "2026-02-01", end_date: "2026-02-28")
      expect(response).to have_http_status(:ok)

      get admin_inventory_reports_variance_path
      expect(response).to have_http_status(:ok)
      expect(date_field_value("start_date")).to eq("2026-02-01")
      expect(date_field_value("end_date")).to eq("2026-02-28")
    end
  end

  describe "explicit params" do
    it "override the session and refresh it" do
      get admin_accounting_expenses_path(start_date: "2026-01-01", end_date: "2026-01-31")
      expect(session[:admin_start_date]).to eq("2026-01-01")

      get admin_accounting_sales_reports_path(start_date: "2026-04-01", end_date: "2026-04-10")
      expect(response).to have_http_status(:ok)
      expect(date_field_value("start_date")).to eq("2026-04-01")
      expect(date_field_value("end_date")).to eq("2026-04-10")
      expect(session[:admin_start_date]).to eq("2026-04-01")
      expect(session[:admin_end_date]).to eq("2026-04-10")
    end
  end

  describe "invalid params" do
    it "do not crash and do not wipe a good session" do
      get admin_accounting_expenses_path(start_date: "2026-05-01", end_date: "2026-05-20")
      expect(session[:admin_start_date]).to eq("2026-05-01")
      expect(session[:admin_end_date]).to eq("2026-05-20")

      get admin_accounting_sales_reports_path(start_date: "not-a-date", end_date: "also-bad")
      expect(response).to have_http_status(:ok)
      expect(date_field_value("start_date")).to eq("2026-05-01")
      expect(date_field_value("end_date")).to eq("2026-05-20")
      expect(session[:admin_start_date]).to eq("2026-05-01")
      expect(session[:admin_end_date]).to eq("2026-05-20")
    end
  end
end
