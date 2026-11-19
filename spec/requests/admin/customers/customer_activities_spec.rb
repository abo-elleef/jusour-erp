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

  def tab!(customer, tab = nil, **params)
    get admin_customer_path(customer, tab: tab, **params), headers: { "Turbo-Frame" => "customer_tab" }
  end

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
      expect(response).to redirect_to(admin_customer_path(cust_a, tab: "activity"))

      tab!(cust_a, "activity")
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

      tab!(cust_a, "activity")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="customer-activities"')
      expect(response.body).not_to include('data-testid="customer-activity-form"')
    end
  end

  describe "the customer page tabs" do
    let(:lead) do
      create(:lead, company: company, created_by: rep_a, assigned_user: rep_a, name: "Gamma Clinic",
        phone: "01011112222")
    end

    it "keeps the lead's history and the customer's own activity in separate tabs" do
      lead.lead_activities.create!(user: rep_a, activity_type: "call", note: "First call with the lead")
      customer = lead.convert!(by: rep_a)
      customer.customer_activities.create!(user: rep_a, activity_type: "meeting", note: "Signed the first order")

      sign_in rep_a
      get admin_customer_path(customer)
      expect(response.body).to include('id="customer_tab"')
      expect(response.body).not_to include("First call with the lead", "Signed the first order")

      tab!(customer)
      expect(response.body).to include('data-testid="customer-origin"', admin_sales_lead_path(lead))
      expect(response.body).to include(admin_customer_path(customer, tab: "lead_history"))
      expect(response.body[/data-testid="recent-activities".*?<\/ul>/m]).to include("Signed the first order")

      tab!(customer, "lead_history")
      expect(response.body).to include(I18n.l(lead.converted_at.to_date, format: :long))
      lead_list = response.body[/data-testid="lead-activities".*?<\/ul>/m]
      expect(lead_list).to include("First call with the lead",
        I18n.t("sales.leads.activity.converted", customer: customer.name))
      expect(lead_list).not_to include("Signed the first order")

      tab!(customer, "activity")
      customer_list = response.body[/data-testid="customer-activities".*?<\/ul>/m]
      expect(customer_list).to include("Signed the first order")
      expect(customer_list).not_to include("First call with the lead")
    end

    it "has no lead history tab for a customer that never was a lead" do
      sign_in rep_a
      tab!(cust_a)
      expect(response.body).to include(admin_customer_path(cust_a, tab: "activity"))
      expect(response.body).not_to include(admin_customer_path(cust_a, tab: "lead_history"), 'data-testid="customer-origin"')

      tab!(cust_a, "lead_history")
      expect(response.body).not_to include('data-testid="lead-activities"')
    end

    it "paginates a long timeline" do
      26.times { |i| cust_a.customer_activities.create!(user: rep_a, activity_type: "note", note: "Entry #{i}") }

      sign_in rep_a
      tab!(cust_a, "activity")
      expect(response.body).to include("Entry 25<")
      expect(response.body).not_to include("Entry 0<")

      tab!(cust_a, "activity", page: 2)
      expect(response.body).to include("Entry 0<")
    end
  end

  describe "a restaurant" do
    let(:restaurant) { create(:company) }
    let(:manager) { create(:user, :owner, company: restaurant) }

    it "shows no activity sections and refuses logging" do
      Current.company = restaurant
      customer = create(:customer, company: restaurant, name: "Walk-in")

      sign_in manager
      tab!(customer)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(admin_customer_path(customer, tab: "orders"))
      expect(response.body).not_to include(admin_customer_path(customer, tab: "activity"),
        'data-testid="recent-activities"', 'data-testid="customer-origin"')

      tab!(customer, "activity")
      expect(response.body).not_to include('data-testid="customer-activities"')

      expect { log!(customer, note: "x") }.not_to change(CustomerActivity, :count)
      expect(response).to redirect_to(admin_root_path)
    end
  end
end
