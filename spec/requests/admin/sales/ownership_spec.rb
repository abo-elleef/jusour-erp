# frozen_string_literal: true

require "rails_helper"

# Bazzar slice E: a salesperson without sales:see_all sees only their own
# leads, customers and invoices (Sales::OwnershipScope). A see-all manager and
# the owner see everything; restaurants are untouched.
RSpec.describe "Sales ownership (own content only)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  # Before the let! records below, so they're built inside this company.
  before { Current.company = company }
  let(:owner) { create(:user, :owner, company: company, name: "Owner") }
  let(:rep_role) do
    Role.create!(company: company, name: "Sales rep", key: "rep",
                 permissions: %w[dashboard:view customers:manage leads:view leads:manage leads:reports])
  end
  let(:boss_role) do
    Role.create!(company: company, name: "Sales manager", key: "boss",
                 permissions: %w[dashboard:view customers:manage leads:view leads:manage leads:reports sales:see_all])
  end
  let(:rep_a) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep Alpha") }
  let(:rep_b) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep Bravo") }
  let(:boss) { create(:user, company: company, role: "custom", role_id: boss_role.id, name: "Boss") }

  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) { create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg") }

  let!(:cust_a) { create(:customer, company: company, name: "Alpha Clinic", customer_type: "commercial", assigned_user: rep_a) }
  let!(:cust_b) { create(:customer, company: company, name: "Bravo Clinic", customer_type: "commercial", assigned_user: rep_b) }
  let!(:cust_none) { create(:customer, company: company, name: "Nobody Clinic", customer_type: "commercial") }


  def invoice_for(customer, user: owner, salesperson: nil, status: nil)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user, salesperson: salesperson,
      location: location, invoice_date: Date.current)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 10_000)
    inv.save!
    inv.update_columns(status: status) if status
    inv
  end

  def credit_note_for(customer, user: owner)
    cn = CreditNote.new(company: company, customer: customer, user: user, location: location,
      credit_note_date: Date.current, restock: false)
    cn.credit_note_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit, unit_price_cents: 5_000)
    cn.save!
    cn
  end

  describe "customers" do
    it "lists only the rep's own customers; managers and the owner see all" do
      sign_in rep_a
      get admin_customers_path
      expect(response.body).to include("Alpha Clinic")
      expect(response.body).not_to include("Bravo Clinic", "Nobody Clinic")

      [boss, owner].each do |user|
        sign_in user
        get admin_customers_path
        expect(response.body).to include("Alpha Clinic", "Bravo Clinic", "Nobody Clinic")
      end
    end

    it "404s another rep's (or an unassigned) customer by URL" do
      sign_in rep_a
      get admin_customer_path(cust_a)
      expect(response).to have_http_status(:ok)

      [cust_b, cust_none].each do |customer|
        get admin_customer_path(customer)
        expect(response).to have_http_status(:not_found)
        get edit_admin_customer_path(customer)
        expect(response).to have_http_status(:not_found)
      end
    end

    it "assigns a customer a rep creates to that rep, ignoring any other assignee" do
      sign_in rep_a
      post admin_customers_path, params: { customer: { name: "New Clinic", phone: "01012345678", assigned_user_id: rep_b.id } }

      expect(Customer.find_by(name: "New Clinic").assigned_user).to eq(rep_a)
    end

    it "lets a manager assign on the form and in bulk, filter unassigned, but not a rep" do
      sign_in boss
      patch admin_customer_path(cust_none), params: { customer: { assigned_user_id: rep_a.id } }
      expect(cust_none.reload.assigned_user).to eq(rep_a)

      get admin_customers_path(assigned_user_id: "none")
      expect(response.body).not_to include("Alpha Clinic", "Bravo Clinic")

      patch bulk_assign_admin_customers_path, params: { customer_ids: [cust_a.id, cust_b.id], assigned_user_id: rep_b.id }
      expect([cust_a.reload, cust_b.reload].map(&:assigned_user)).to eq([rep_b, rep_b])

      sign_in rep_b
      patch bulk_assign_admin_customers_path, params: { customer_ids: [cust_a.id], assigned_user_id: rep_a.id }
      expect(cust_a.reload.assigned_user).to eq(rep_b)
      patch admin_customer_path(cust_a), params: { customer: { assigned_user_id: rep_a.id } }
      expect(cust_a.reload.assigned_user).to eq(rep_b)
    end
  end

  describe "customer invoices" do
    let!(:inv_a) { invoice_for(cust_a) }
    let!(:inv_b) { invoice_for(cust_b) }
    let!(:inv_recorded) { invoice_for(cust_b, user: rep_a) }
    let!(:inv_sold) { invoice_for(cust_none, salesperson: rep_a) }

    it "lists the rep's customers' invoices plus those they recorded or sold" do
      sign_in rep_a
      get admin_sales_customer_invoices_path
      expect(response.body).to include(inv_a.invoice_number, inv_recorded.invoice_number, inv_sold.invoice_number)
      expect(response.body).not_to include(inv_b.invoice_number)

      sign_in boss
      get admin_sales_customer_invoices_path
      expect(response.body).to include(inv_a.invoice_number, inv_b.invoice_number)
    end

    it "404s another rep's invoice by URL and for actions" do
      sign_in rep_a
      get admin_sales_customer_invoice_path(inv_b)
      expect(response).to have_http_status(:not_found)

      sign_in rep_a # a rescued 404 doesn't carry the session cookie forward
      patch void_admin_sales_customer_invoice_path(inv_b)
      expect(response).to have_http_status(:not_found)
      expect(inv_b.reload.status).to eq("draft")

      sign_in rep_a
      get admin_sales_customer_invoice_path(inv_a)
      expect(response).to have_http_status(:ok)
    end

    it "offers only the rep's customers in the pickers and refuses another rep's customer" do
      sign_in rep_a
      get new_admin_sales_customer_invoice_path
      expect(response.body).to include("Alpha Clinic")
      expect(response.body).not_to include("Bravo Clinic")

      expect {
        post admin_sales_customer_invoices_path, params: { customer_invoice: {
          customer_id: cust_b.id, location_id: location.id, invoice_date: Date.current.iso8601,
          customer_invoice_lines_attributes: { "0" => { ingredient_id: ingredient.id, quantity: 1, unit: "kg", unit_price_pounds: "10" } }
        } }
      }.not_to change(CustomerInvoice, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "ANDs ownership with the role × stage grid, keeping invoices they recorded or sold" do
      CustomerInvoice::STAGES.each do |stage|
        Sales::StageAccess.create!(role: rep_role, stage: stage, can_see: stage != "draft", notify: false)
      end

      sign_in rep_a
      get admin_sales_customer_invoices_path
      expect(response.body).not_to include(inv_a.invoice_number) # theirs by customer, but draft is hidden
      expect(response.body).to include(inv_recorded.invoice_number, inv_sold.invoice_number)

      get admin_sales_customer_invoice_path(inv_a)
      expect(response).to redirect_to(admin_sales_customer_invoices_path)
    end

    it "keeps a payment approver seeing invoices pending their approval" do
      treasury = Treasury.create!(name: "Wallet", treasury_type: "bank", balance_cents: 0, opening_balance_cents: 0, company: company)
      method = create(:sales_payment_method, company: company, treasury: treasury, name: "Wallet A")
      method.approvers << rep_a
      pending = invoice_for(cust_b)
      pending.update_columns(status: "pending_payment_confirmation", payment_method: "online", sales_payment_method_id: method.id)

      sign_in rep_a
      get admin_sales_customer_invoices_path
      expect(response.body).to include(pending.invoice_number)
      get admin_sales_customer_invoice_path(pending)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "credit notes" do
    let!(:cn_a) { credit_note_for(cust_a) }
    let!(:cn_b) { credit_note_for(cust_b) }

    it "lists and opens only the rep's own credit notes" do
      sign_in rep_a
      get admin_sales_credit_notes_path
      expect(response.body).to include(cn_a.credit_note_number)
      expect(response.body).not_to include(cn_b.credit_note_number)

      get admin_sales_credit_note_path(cn_b)
      expect(response).to have_http_status(:not_found)

      get new_admin_sales_credit_note_path
      expect(response.body).to include("Alpha Clinic")
      expect(response.body).not_to include("Bravo Clinic")
    end
  end

  describe "customer statements" do
    before do
      invoice_for(cust_a)
      invoice_for(cust_b)
    end

    it "lists and opens only the rep's own customers" do
      sign_in rep_a
      get admin_sales_customer_statements_path
      expect(response.body).to include("Alpha Clinic")
      expect(response.body).not_to include("Bravo Clinic")

      get admin_sales_customer_statement_path(cust_b)
      expect(response).to have_http_status(:not_found)

      sign_in boss
      get admin_sales_customer_statements_path
      expect(response.body).to include("Alpha Clinic", "Bravo Clinic")
    end
  end

  describe "leads" do
    let!(:lead_a) { create(:lead, company: company, name: "Lead Alpha", created_by: owner, assigned_user: rep_a) }
    let!(:lead_b) { create(:lead, company: company, name: "Lead Bravo", created_by: owner, assigned_user: rep_b) }

    it "lists only the rep's leads and 404s another rep's lead" do
      sign_in rep_a
      get admin_sales_leads_path
      expect(response.body).to include("Lead Alpha")
      expect(response.body).not_to include("Lead Bravo")

      get admin_sales_lead_path(lead_b)
      expect(response).to have_http_status(:not_found)
      post admin_sales_lead_lead_activities_path(lead_b), params: { lead_activity: { activity_type: "call", note: "x" } }
      expect(response).to have_http_status(:not_found)

      sign_in boss
      get admin_sales_leads_path
      expect(response.body).to include("Lead Alpha", "Lead Bravo")
    end

    it "keeps a lead a rep creates on that rep" do
      sign_in rep_a
      post admin_sales_leads_path, params: { lead: { name: "Fresh", phone: "01099999999", assigned_user_id: rep_b.id } }
      expect(Lead.find_by(name: "Fresh").assigned_user).to eq(rep_a)
    end

    it "assigns the converted customer to the lead's salesperson" do
      sign_in rep_a
      post convert_admin_sales_lead_path(lead_a)
      expect(lead_a.reload.customer.assigned_user).to eq(rep_a)
    end

    it "shows a rep only their own numbers in the lead reports" do
      sign_in rep_a
      get admin_sales_lead_reports_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Rep Alpha")
      expect(response.body).not_to include("Rep Bravo")
    end
  end

  describe "sales reports" do
    before do
      invoice_for(cust_a, status: "historical")
      invoice_for(cust_b, status: "historical")
    end

    it "narrows every figure to the rep's own sales" do
      own = Sales::SalesReportService.new(Date.current, Date.current, ownership: Sales::OwnershipScope.for(rep_a))
      all = Sales::SalesReportService.new(Date.current, Date.current, ownership: Sales::OwnershipScope.for(boss))
      expect(own.summary[:invoice_count]).to eq(1)
      expect(all.summary[:invoice_count]).to eq(2)

      sign_in rep_a
      get admin_sales_reports_path(section: "customer")
      expect(response.body).to include("Alpha Clinic")
      expect(response.body).not_to include("Bravo Clinic")
    end
  end

  describe "a restaurant company" do
    let(:restaurant) { create(:company, business_type: "restaurant") }
    let(:floor_role) do
      Role.create!(company: restaurant, name: "Floor", key: "floor", permissions: %w[customers:manage pos:access])
    end
    let(:floor) { create(:user, company: restaurant, role: "custom", role_id: floor_role.id) }

    it "is never narrowed — POS search and the customers list show every customer" do
      Current.company = restaurant
      create(:customer, company: restaurant, name: "Walk-in Ahmed", phone: "01011112222")
      create(:customer, company: restaurant, name: "Walk-in Sara", phone: "01033334444")

      expect(Sales::OwnershipScope.for(floor)).not_to be_limited

      sign_in floor
      get customers_search_path(q: "Walk")
      expect(response.body).to include("Walk-in Ahmed", "Walk-in Sara")

      get admin_customers_path
      expect(response.body).to include("Walk-in Ahmed", "Walk-in Sara")
    end
  end
end
