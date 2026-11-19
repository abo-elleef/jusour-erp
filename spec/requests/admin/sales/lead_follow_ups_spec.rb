# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Lead follow-up cadence (admin)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }

  before do
    Current.company = company
    sign_in owner
  end

  it "saves both settings, blank meaning off, and accepts Arabic digits" do
    patch admin_settings_path, params: { lead_first_follow_up_days: "٢", lead_follow_up_every_days: "" }

    row = CompanySetting.find_by!(company: company)
    expect(row.lead_first_follow_up_days).to eq(2)
    expect(row.lead_follow_up_every_days).to eq(0)
  end

  it "shows the settings for a company with leads" do
    get admin_settings_path
    expect(response.body).to include('data-testid="settings-lead-follow-ups"')
  end

  it "hides the settings for a restaurant" do
    company.update!(business_type: "restaurant", feature_overrides: {})
    get admin_settings_path
    expect(response.body).not_to include('data-testid="settings-lead-follow-ups"')
  end

  it "pre-fills the new lead form with today + first-follow-up days" do
    Setting.set("lead_first_follow_up_days", 2)
    get new_admin_sales_lead_path
    expect(response.body).to include(%(value="#{(Date.current + 2).iso8601}"))
  end

  describe "logging an activity" do
    let(:lead) { create(:lead, created_by: owner, next_follow_up_at: Date.current - 1) }

    it "pre-fills the next follow-up on the log form" do
      get admin_sales_lead_path(lead)
      expect(response.body).to include(%(value="#{(Date.current + 3).iso8601}"))
    end

    it "moves the lead's date to the cadence when the field is blank" do
      post admin_sales_lead_lead_activities_path(lead),
        params: { lead_activity: { activity_type: "call", note: "Called", next_follow_up_on: "" } }
      expect(lead.reload.next_follow_up_at).to eq(Date.current + 3)
    end

    it "keeps the date the rep picked" do
      post admin_sales_lead_lead_activities_path(lead),
        params: { lead_activity: { activity_type: "call", note: "Called", next_follow_up_on: (Date.current + 9).iso8601 } }
      expect(lead.reload.next_follow_up_at).to eq(Date.current + 9)
    end
  end

  it "filters the list to open leads that are due" do
    due = create(:lead, created_by: owner, name: "Due Pharmacy", next_follow_up_at: Date.current)
    create(:lead, created_by: owner, name: "Lost Pharmacy", next_follow_up_at: Date.current,
      stage: "lost", lost_reason: "price")
    create(:lead, created_by: owner, name: "Later Pharmacy", next_follow_up_at: Date.current + 4)

    get admin_sales_leads_path(due_only: 1)
    expect(response.body).to include(due.name)
    expect(response.body).not_to include("Lost Pharmacy")
    expect(response.body).not_to include("Later Pharmacy")
  end
end
