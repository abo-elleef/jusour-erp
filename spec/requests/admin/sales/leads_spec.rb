# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Sales::Leads", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  let(:owner) { create(:user, :owner, company: company) }
  let(:rep) { create(:user, company: company, name: "Rep One", role: "manager") }

  before do
    Current.company = company
    sign_in owner
  end

  it "defaults a new lead's assignee to its creator" do
    post admin_sales_leads_path, params: { lead: { name: "Acme Pharmacy", phone: "5551234" } }

    lead = Lead.last
    expect(lead.assigned_user).to eq(owner)
    expect(lead.created_by).to eq(owner)
  end

  it "is unavailable to a company without the leads feature" do
    company.update!(business_type: "restaurant", feature_overrides: {})

    get admin_sales_leads_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "reassigns a lead to another teammate via the edit form" do
    lead = create(:lead, created_by: owner, assigned_user: owner)

    patch admin_sales_lead_path(lead), params: { lead: { assigned_user_id: rep.id } }

    expect(lead.reload.assigned_user).to eq(rep)
    expect(lead.lead_activities.last.activity_type).to eq("assignment_change")
  end

  it "moves a lead's stage via the edit form" do
    lead = create(:lead, created_by: owner, stage: "new")

    patch admin_sales_lead_path(lead), params: { lead: { stage: "contacted" } }

    expect(lead.reload.stage).to eq("contacted")
    expect(lead.lead_activities.last.activity_type).to eq("stage_change")
  end

  it "ignores an attempt to jump straight to a terminal stage through the edit form" do
    lead = create(:lead, created_by: owner, stage: "new")

    patch admin_sales_lead_path(lead), params: { lead: { stage: "converted" } }

    expect(lead.reload.stage).to eq("new")
  end

  it "converts a lead into a real customer and redirects to a new invoice for them" do
    lead = create(:lead, created_by: owner, name: "Acme Pharmacy", phone: "5551234", email: "acme@test.com")

    post convert_admin_sales_lead_path(lead)

    customer = Customer.find_by(name: "Acme Pharmacy")
    expect(customer).to be_present
    expect(customer.originating_lead).to eq(lead)
    expect(lead.reload).to be_converted
    expect(response).to redirect_to(new_admin_sales_customer_invoice_path(customer_id: customer.id))
  end

  it "marks a lead lost with a reason" do
    lead = create(:lead, created_by: owner)

    post mark_lost_admin_sales_lead_path(lead), params: { lost_reason: "price", lost_reason_note: "Too expensive" }

    lead.reload
    expect(lead).to be_lost
    expect(lead.lost_reason).to eq("price")
  end

  it "requires leads:manage to convert, even with leads:view" do
    sub_manager = create(:user, company: company, role: "sub_manager")
    sub_manager.effective_role.update!(permissions: sub_manager.effective_role.permissions - ["leads:manage"])
    sign_in sub_manager
    lead = create(:lead, created_by: owner)

    post convert_admin_sales_lead_path(lead)

    expect(response).to redirect_to(admin_sales_leads_path)
    expect(lead.reload).not_to be_converted
  end

  describe "phone rules" do
    def error_box
      Nokogiri::HTML(response.body).at("[data-testid=lead-errors]")
    end

    it "refuses a repeated phone and links to the existing lead" do
      existing = create(:lead, created_by: owner, name: "Dr. Mona", phone: "01011111111")

      expect {
        post admin_sales_leads_path, params: { lead: { name: "Dr. Mona again", phone: "٠١٠ ١١١١ ١١١١" } }
      }.not_to change(Lead, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error_box.text).to include("Dr. Mona")
      expect(error_box.at("a")["href"]).to eq(admin_sales_lead_path(existing))
    end

    it "refuses a customer's phone and links to the customer's page" do
      customer = create(:customer, name: "Al Shifa Clinic", phone: "01033333333")

      post admin_sales_leads_path, params: { lead: { name: "Al Shifa", phone: "01099999999", phone_secondary: "01033333333" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(error_box.text).to include("Al Shifa Clinic")
      expect(error_box.at("a")["href"]).to eq(admin_customer_path(customer))
    end

    it "refuses a 10-digit phone only when the company setting is on" do
      post admin_sales_leads_path, params: { lead: { name: "Short one", phone: "0101234567" } }
      expect(response).to have_http_status(:redirect)

      patch admin_settings_path, params: { require_eleven_digit_phones: "1" }
      post admin_sales_leads_path, params: { lead: { name: "Short two", phone: "0101234568" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(error_box.text).to include(I18n.t("phones.errors.eleven_digits", field: Lead.human_attribute_name(:phone)))
    end
  end
end
