# frozen_string_literal: true

require "rails_helper"

# Bazzar slice F: a customer's own activity log, plus the lead it came from and
# that lead's timeline, on the customer page.
RSpec.describe "Customer activities", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  before { Current.company = company }

  let(:owner) { create(:user, :owner, company: company, name: "Owner") }
  let(:rep_role) do
    Role.create!(company: company, name: "Sales rep", key: "rep",
                 permissions: %w[dashboard:view customers:manage leads:view leads:manage])
  end
  let(:viewer_role) do
    Role.create!(company: company, name: "Viewer", key: "viewer",
                 permissions: %w[dashboard:view customers:manage sales:see_all])
  end
  let(:rep_a) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep Alpha") }
  let(:rep_b) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep Bravo") }
  let(:viewer) { create(:user, company: company, role: "custom", role_id: viewer_role.id, name: "Viewer") }

  let!(:cust_a) { create(:customer, company: company, name: "Alpha Clinic", assigned_user: rep_a) }
  let!(:cust_b) { create(:customer, company: company, name: "Bravo Clinic", assigned_user: rep_b) }

  def log!(customer, note:, type: "call")
    post admin_customer_customer_activities_path(customer),
      params: { customer_activity: { activity_type: type, note: note } }
  end

  describe "logging" do
    it "logs an activity on the rep's own customer and shows it on the page" do
      sign_in rep_a
      expect { log!(cust_a, note: "Visited the clinic") }.to change(CustomerActivity, :count).by(1)

      activity = CustomerActivity.last
      expect(activity).to have_attributes(customer: cust_a, user: rep_a, activity_type: "call")
      expect(response).to redirect_to(admin_customer_path(cust_a, anchor: "customer-activities"))

      get admin_customer_path(cust_a)
      expect(response.body).to include("Visited the clinic", "Rep Alpha")
    end

    it "requires a note" do
      sign_in rep_a
      expect { log!(cust_a, note: "") }.not_to change(CustomerActivity, :count)
      expect(flash[:alert]).to be_present
    end

    it "refuses a type that is not rep-loggable" do
      sign_in rep_a
      expect { log!(cust_a, note: "x", type: "stage_change") }.not_to change(CustomerActivity, :count)
    end

    it "404s a limited rep on another rep's customer" do
      sign_in rep_a
      expect { log!(cust_b, note: "Not mine") }.not_to change(CustomerActivity, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "needs leads:manage to log, and hides the form without it" do
      sign_in viewer
      expect { log!(cust_a, note: "x") }.not_to change(CustomerActivity, :count)
      expect(response).to redirect_to(admin_customers_path)

      get admin_customer_path(cust_a)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("customers.activities.customer_heading"))
      expect(response.body).not_to include('data-testid="customer-activity-form"')
    end
  end

  describe "the customer page history" do
    let(:lead) do
      create(:lead, company: company, created_by: rep_a, assigned_user: rep_a, name: "Gamma Clinic",
        phone: "01011112222")
    end

    it "shows the origin lead, its timeline, and the customer's own timeline apart" do
      lead.lead_activities.create!(user: rep_a, activity_type: "call", note: "First call with the lead")
      customer = lead.convert!(by: rep_a)
      customer.customer_activities.create!(user: rep_a, activity_type: "meeting", note: "Signed the first order")

      sign_in rep_a
      get admin_customer_path(customer)

      body = response.body
      expect(body).to include('data-testid="customer-origin"')
      expect(body).to include(admin_sales_lead_path(lead))
      expect(body).to include(I18n.l(lead.converted_at.to_date, format: :long))

      lead_list = body[/data-testid="lead-activities".*?<\/ul>/m]
      customer_list = body[/data-testid="customer-activities".*?<\/ul>/m]
      expect(lead_list).to include("First call with the lead")
      expect(lead_list).to include(I18n.t("sales.leads.activity.converted", customer: customer.name))
      expect(lead_list).not_to include("Signed the first order")
      expect(customer_list).to include("Signed the first order")
      expect(customer_list).not_to include("First call with the lead")
    end

    it "shows only the customer's own timeline for a customer that never was a lead" do
      sign_in rep_a
      get admin_customer_path(cust_a)

      expect(response.body).to include('data-testid="customer-activities"')
      expect(response.body).not_to include('data-testid="customer-origin"', 'data-testid="lead-activities"')
    end

    it "caps a long timeline and offers show all" do
      21.times { |i| cust_a.customer_activities.create!(user: rep_a, activity_type: "note", note: "Entry #{i}") }

      sign_in rep_a
      get admin_customer_path(cust_a)
      expect(response.body.scan('data-testid="customer-activities"').size).to eq(1)
      expect(response.body).to include(I18n.t("customers.activities.show_all"))
      expect(response.body).not_to include("Entry 0<")

      get admin_customer_path(cust_a, customer_activities: "all")
      expect(response.body).to include("Entry 0<")
      expect(response.body).not_to include(I18n.t("customers.activities.show_all"))
    end
  end

  describe "a restaurant" do
    let(:restaurant) { create(:company) }
    let(:manager) { create(:user, :owner, company: restaurant) }

    it "shows no activity sections and refuses logging" do
      Current.company = restaurant
      customer = create(:customer, company: restaurant, name: "Walk-in")

      sign_in manager
      get admin_customer_path(customer)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-testid="customer-activities"', 'data-testid="customer-origin"')

      expect { log!(customer, note: "x") }.not_to change(CustomerActivity, :count)
      expect(response).to redirect_to(admin_root_path)
    end
  end
end
