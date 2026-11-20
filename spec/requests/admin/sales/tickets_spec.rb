# frozen_string_literal: true

require "rails_helper"

# Bazzar slice G1: customer tickets — opened by staff from a customer or an
# invoice, worked through a comment thread, resolved by reps, closed by managers.
RSpec.describe "Customer tickets", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company, business_type: "distribution") }
  before { Current.company = company }

  let(:owner) { create(:user, :owner, company: company, name: "Owner") }
  let(:rep_role) do
    Role.create!(company: company, name: "Sales rep", key: "rep",
                 permissions: %w[dashboard:view customers:manage leads:view leads:manage tickets:manage])
  end
  let(:manager_role) do
    Role.create!(company: company, name: "Sales manager", key: "boss",
                 permissions: %w[dashboard:view customers:manage leads:view sales:see_all tickets:manage tickets:assign])
  end
  let(:plain_role) do
    Role.create!(company: company, name: "No tickets", key: "plain", permissions: %w[dashboard:view customers:manage])
  end
  let(:rep_a) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep Alpha") }
  let(:rep_b) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep Bravo") }
  let(:boss) { create(:user, company: company, role: "custom", role_id: manager_role.id, name: "Boss") }
  let(:plain) { create(:user, company: company, role: "custom", role_id: plain_role.id, name: "Plain") }

  let(:location) { create(:location, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: create(:ingredient_category, company: company),
      name: "Kit", unit: "kg")
  end
  let!(:cust_a) { create(:customer, company: company, name: "Alpha Clinic", assigned_user: rep_a) }
  let!(:cust_b) { create(:customer, company: company, name: "Bravo Clinic", assigned_user: rep_b) }

  def invoice_for(customer)
    inv = CustomerInvoice.new(company: company, customer: customer, user: owner, location: location,
      invoice_date: Date.current)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: "kg", unit_price_cents: 10_000)
    inv.save!
    inv
  end

  def image
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/storefront_product.png"), "image/png")
  end

  def open!(customer, **attrs)
    post admin_sales_tickets_path, params: { ticket: { customer_id: customer.id, subject: "Broken kit" }.merge(attrs) }
  end

  describe "opening" do
    it "opens a ticket with images from the customer's Tickets tab" do
      sign_in rep_a
      get admin_customer_path(cust_a, tab: "tickets"), headers: { "Turbo-Frame" => "customer_tab" }
      expect(response.body).to include(new_admin_sales_ticket_path(customer_id: cust_a.id))

      get new_admin_sales_ticket_path(customer_id: cust_a.id)
      expect(response).to have_http_status(:ok)

      category = TicketCategory.find_by!(key: "product_quality")
      expect { open!(cust_a, ticket_category_id: category.id, priority: "urgent", images: [image]) }
        .to change(Ticket, :count).by(1)
      ticket = Ticket.find_by!(customer: cust_a)
      expect(ticket).to have_attributes(customer: cust_a, opened_by: rep_a, priority: "urgent", status: "open")
      expect(ticket.images.count).to eq(1)
      expect(response).to redirect_to(admin_sales_ticket_path(ticket))

      follow_redirect!
      expect(response.body).to include("T-0001", "Broken kit")
    end

    it "opens from an invoice, pre-filling customer and invoice, and lists it on the invoice" do
      invoice = invoice_for(cust_a)
      sign_in rep_a
      get admin_sales_customer_invoice_path(invoice)
      expect(response.body).to include(
        ERB::Util.html_escape(new_admin_sales_ticket_path(customer_id: cust_a.id, customer_invoice_id: invoice.id))
      )

      get new_admin_sales_ticket_path(customer_id: cust_a.id, customer_invoice_id: invoice.id)
      expect(response.body).to include(%(<option selected="selected" value="#{invoice.id}"))

      open!(cust_a, customer_invoice_id: invoice.id)
      expect(Ticket.find_by!(customer: cust_a).customer_invoice).to eq(invoice)

      get admin_sales_customer_invoice_path(invoice)
      expect(response.body).to include("T-0001")
    end

    it "won't open a ticket on another rep's customer, and ignores a rep's chosen assignee" do
      sign_in rep_a
      open!(cust_a, assigned_user_id: rep_b.id)
      expect(Ticket.find_by!(customer: cust_a).assigned_user).to be_nil

      get new_admin_sales_ticket_path(customer_id: cust_b.id)
      expect(response).to have_http_status(:not_found)
      sign_in rep_a
      expect { open!(cust_b) }.not_to change(Ticket, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "lets a manager pick the assignee" do
      sign_in boss
      open!(cust_b, assigned_user_id: rep_b.id)
      expect(Ticket.find_by!(customer: cust_b).assigned_user).to eq(rep_b)
    end
  end

  describe "working a ticket" do
    let!(:ticket) { Ticket.create!(customer: cust_a, opened_by: rep_a, subject: "Late delivery", assigned_user: rep_a) }

    it "adds a comment with an image" do
      sign_in rep_a
      expect do
        post admin_sales_ticket_ticket_comments_path(ticket), params: { ticket_comment: { body: "Called them", images: [image] } }
      end.to change(TicketComment, :count).by(1)
      expect(ticket.comments.find_by!(body: "Called them").images.count).to eq(1)

      get admin_sales_ticket_path(ticket)
      expect(response.body).to include("Called them")
    end

    it "lets a rep resolve but not close; a manager closes and reopens" do
      sign_in rep_a
      patch change_status_admin_sales_ticket_path(ticket), params: { status: "resolved", note: "Re-sent" }
      expect(ticket.reload.status).to eq("resolved")

      get admin_sales_ticket_path(ticket)
      expect(response.body).not_to include(%(data-testid="ticket-move-closed"))
      expect(response.body).to include(%(data-testid="close-needs-manager"))
      patch change_status_admin_sales_ticket_path(ticket), params: { status: "closed" }
      expect(ticket.reload.status).to eq("resolved")
      expect(flash[:alert]).to be_present

      sign_in boss
      patch change_status_admin_sales_ticket_path(ticket), params: { status: "closed" }
      expect(ticket.reload.status).to eq("closed")
      patch change_status_admin_sales_ticket_path(ticket), params: { status: "open" }
      expect(ticket.reload.status).to eq("open")
    end

    it "lets a manager reassign, not a rep" do
      sign_in rep_a
      patch reassign_admin_sales_ticket_path(ticket), params: { assigned_user_id: rep_b.id }
      expect(ticket.reload.assigned_user).to eq(rep_a)

      sign_in boss
      patch reassign_admin_sales_ticket_path(ticket), params: { assigned_user_id: rep_b.id }
      expect(ticket.reload.assigned_user).to eq(rep_b)
      expect(Notification.where(recipient: rep_b).pluck(Arel.sql("params->>'message_key'"))).to eq(["ticket_assigned"])
    end
  end

  describe "visibility" do
    let!(:ticket_a) { Ticket.create!(customer: cust_a, opened_by: boss, subject: "Alpha issue") }
    let!(:ticket_b) { Ticket.create!(customer: cust_b, opened_by: boss, subject: "Bravo issue", assigned_user: rep_b) }

    it "shows a limited rep only their tickets; another rep's ticket is a 404" do
      sign_in rep_a
      get admin_sales_tickets_path
      expect(response.body).to include("Alpha issue")
      expect(response.body).not_to include("Bravo issue")

      get admin_sales_ticket_path(ticket_b)
      expect(response).to have_http_status(:not_found)
      post admin_sales_ticket_ticket_comments_path(ticket_b), params: { ticket_comment: { body: "hi" } }
      expect(response).to have_http_status(:not_found)
    end

    it "shows a tickets:assign holder and the owner everything" do
      [boss, owner].each do |user|
        sign_in user
        get admin_sales_tickets_path
        expect(response.body).to include("Alpha issue", "Bravo issue")
      end
    end

    it "keeps users without a tickets permission out" do
      sign_in plain
      get admin_sales_tickets_path
      expect(response).to redirect_to(admin_root_path)
    end

    it "filters by status, assignee, 'my tickets' and search, and sorts" do
      ticket_b.change_status!("resolved", by: boss)
      sign_in boss

      get admin_sales_tickets_path(status: "resolved")
      expect(response.body).to include("Bravo issue")
      expect(response.body).not_to include("Alpha issue")

      get admin_sales_tickets_path(assigned_user_id: "none")
      expect(response.body).to include("Alpha issue")
      expect(response.body).not_to include("Bravo issue")

      get admin_sales_tickets_path(q: "T-0002")
      expect(response.body).to include("Bravo issue")
      expect(response.body).not_to include("Alpha issue")

      sign_in rep_b
      get admin_sales_tickets_path(mine: "1")
      expect(response.body).to include("Bravo issue")

      sign_in boss
      %w[number subject customer status priority assigned_user created_at].each do |sort|
        get admin_sales_tickets_path(sort: sort, dir: "asc")
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "customer timeline" do
    it "shows opening and resolving on the customer's activity tab, linked to the ticket" do
      sign_in rep_a
      open!(cust_a)
      ticket = Ticket.find_by!(customer: cust_a)
      patch change_status_admin_sales_ticket_path(ticket), params: { status: "resolved" }

      get admin_customer_path(cust_a, tab: "activity"), headers: { "Turbo-Frame" => "customer_tab" }
      expect(response.body).to include(admin_sales_ticket_path(ticket), "T-0001 · Broken kit")
    end
  end

  describe "ticket categories (Settings)" do
    it "lets a manager edit categories and set a default handler; a rep can't" do
      category = TicketCategory.find_by!(key: "delivery_problem")
      sign_in rep_a
      get admin_ticket_categories_path
      expect(response).to redirect_to(admin_root_path)

      sign_in boss
      get admin_ticket_categories_path
      expect(response.body).to include("Delivery problem")
      patch admin_ticket_category_path(category), params: { ticket_category: { default_handler_id: rep_b.id, active: "1" } }
      expect(category.reload.default_handler).to eq(rep_b)

      post admin_ticket_categories_path, params: { ticket_category: { name: "Warranty", name_ar: "الضمان", active: "1" } }
      expect(TicketCategory.find_by(name: "Warranty")).to be_present
    end
  end

  describe "restaurants" do
    let(:restaurant) { create(:company, business_type: "restaurant") }

    it "has no tickets area, tab or settings page" do
      Current.company = restaurant
      restaurant_owner = create(:user, :owner, company: restaurant)
      customer = create(:customer, company: restaurant, name: "Diner")
      sign_in restaurant_owner

      get admin_sales_tickets_path
      expect(response).to redirect_to(admin_root_path)
      get admin_ticket_categories_path
      expect(response).to redirect_to(admin_root_path)
      get admin_customer_path(customer), headers: { "Turbo-Frame" => "customer_tab" }
      expect(response.body).not_to include(%(tab=tickets))
    end
  end
end
