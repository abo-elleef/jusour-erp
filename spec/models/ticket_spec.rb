# frozen_string_literal: true

require "rails_helper"

# Bazzar slice G1: core customer tickets.
RSpec.describe Ticket, type: :model do
  let(:company) { create(:company, business_type: "distribution") }
  before { Current.company = company }

  let(:owner) { create(:user, :owner, company: company, name: "Owner") }
  let(:rep_role) do
    Role.create!(company: company, name: "Sales rep", key: "rep",
                 permissions: %w[customers:manage leads:view leads:manage tickets:manage])
  end
  let(:manager_role) do
    Role.create!(company: company, name: "Support lead", key: "lead",
                 permissions: %w[customers:manage tickets:manage tickets:assign])
  end
  let(:rep) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep") }
  let(:rep_b) { create(:user, company: company, role: "custom", role_id: rep_role.id, name: "Rep B") }
  let(:manager) { create(:user, company: company, role: "custom", role_id: manager_role.id, name: "Lead") }
  let(:customer) { create(:customer, company: company, name: "Alpha Clinic", assigned_user: rep) }

  def open_ticket(by: rep, **attrs)
    Ticket.create!({ customer: customer, opened_by: by, subject: "Broken kit" }.merge(attrs))
  end

  describe "numbering" do
    it "numbers tickets per company, shown as T-0001" do
      first = open_ticket
      second = open_ticket
      expect([first.number, second.number]).to eq([1, 2])
      expect(second.display_number).to eq("T-0002")

      other = create(:company, business_type: "distribution")
      Current.company = other
      other_customer = create(:customer, company: other)
      other_user = create(:user, :owner, company: other)
      expect(Ticket.create!(customer: other_customer, opened_by: other_user, subject: "x").number).to eq(1)
    end

    # Transactional tests share one connection across threads, so this is a
    # smoke check; the advisory lock and the unique index are the guarantee.
    it "hands out distinct numbers when tickets are opened at once" do
      customer_id = customer.id
      opener_id = rep.id
      numbers = Array.new(4) do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Current.company = company
            Ticket.create!(customer_id: customer_id, opened_by_id: opener_id, subject: "race #{i}").number
          end
        end
      end.map(&:value)
      expect(numbers.sort).to eq([1, 2, 3, 4])
    end
  end

  describe "defaults" do
    it "defaults to open / normal and gives the ticket to the category's default handler" do
      category = TicketCategory.find_by!(key: "delivery_problem")
      category.update!(default_handler: manager)

      ticket = open_ticket(ticket_category: category)
      expect(ticket).to have_attributes(status: "open", priority: "normal", assigned_user: manager)
    end

    it "keeps an assignee picked on purpose, and skips an inactive default handler" do
      category = TicketCategory.find_by!(key: "other")
      category.update!(default_handler: manager)
      expect(open_ticket(ticket_category: category, assigned_user: rep_b).assigned_user).to eq(rep_b)

      manager.update!(active: false)
      expect(open_ticket(ticket_category: category).assigned_user).to be_nil
    end

    it "seeds the five categories for a new company" do
      expect(TicketCategory.pluck(:key)).to match_array(
        %w[product_quality wrong_or_missing_item delivery_problem price_or_billing other]
      )
      expect(TicketCategory.find_by(key: "other").name_ar).to eq("أخرى")
    end
  end

  describe "status transitions" do
    it "lets a rep work a ticket up to resolved, stamping resolved_at and writing the timeline" do
      ticket = open_ticket
      ticket.change_status!("in_progress", by: rep)
      ticket.change_status!("resolved", by: rep, note: "Replaced the kit")

      expect(ticket.reload.status).to eq("resolved")
      expect(ticket.resolved_at).to be_present
      entries = ticket.comments.where(kind: "status_change")
      expect(entries.map { |c| c.data.values_at("from", "to") }).to eq([%w[open in_progress], %w[in_progress resolved]])
      expect(entries.last.body).to eq("Replaced the kit")
    end

    it "lets only tickets:assign (or the owner) close" do
      ticket = open_ticket
      ticket.change_status!("resolved", by: rep)

      expect(ticket.can_move_to?("closed", rep)).to be(false)
      expect { ticket.change_status!("closed", by: rep) }.to raise_error(Ticket::NotAllowed)
      expect(ticket.reload.status).to eq("resolved")

      ticket.change_status!("closed", by: manager)
      expect(ticket.reload).to have_attributes(status: "closed")
      expect(ticket.closed_at).to be_present
      expect(open_ticket.can_move_to?("closed", owner)).to be(true)
    end

    it "reopens a resolved or closed ticket (manager only), clearing the stamps" do
      ticket = open_ticket
      ticket.change_status!("resolved", by: rep)
      expect { ticket.change_status!("open", by: rep) }.to raise_error(Ticket::NotAllowed)

      ticket.change_status!("closed", by: manager)
      ticket.change_status!("open", by: manager)
      expect(ticket.reload).to have_attributes(status: "open", resolved_at: nil, closed_at: nil)
    end

    it "refuses moves that aren't in the flow" do
      ticket = open_ticket
      expect { ticket.change_status!("open", by: manager) }.to raise_error(Ticket::NotAllowed)
      ticket.change_status!("closed", by: manager)
      expect { ticket.change_status!("resolved", by: manager) }.to raise_error(Ticket::NotAllowed)
      expect(ticket.next_statuses_for(rep)).to eq([])
      expect(ticket.next_statuses_for(manager)).to eq(["open"])
    end
  end

  describe "reassigning and comments" do
    it "lets only a manager reassign, with a timeline entry" do
      ticket = open_ticket
      expect { ticket.reassign!(to: rep_b, by: rep) }.to raise_error(Ticket::NotAllowed)

      ticket.reassign!(to: rep_b, by: manager)
      expect(ticket.reload.assigned_user).to eq(rep_b)
      entry = ticket.comments.find_by(kind: "assignment_change")
      expect(entry.data).to include("to_id" => rep_b.id, "to_name" => "Rep B")
    end

    it "needs a body or an image on a comment" do
      ticket = open_ticket
      expect { ticket.add_comment!(by: rep, body: " ") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(ticket.add_comment!(by: rep, body: "Called the clinic").body).to eq("Called the clinic")
    end

    it "rejects a non-image upload" do
      ticket = open_ticket
      file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/not_an_image.txt"), "text/plain")
      expect { ticket.add_comment!(by: rep, body: "see file", images: [file]) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "links" do
    it "refuses another customer's invoice" do
      other = create(:customer, company: company, name: "Other")
      location = create(:location, company: company)
      category = create(:ingredient_category, company: company)
      ingredient = create(:ingredient, company: company, ingredient_category: category, unit: "kg")
      invoice = CustomerInvoice.new(company: company, customer: other, user: owner, location: location,
        invoice_date: Date.current)
      invoice.customer_invoice_lines.build(ingredient: ingredient, quantity: 1, unit: "kg", unit_price_cents: 1_000)
      invoice.save!

      ticket = Ticket.new(customer: customer, opened_by: rep, subject: "x", customer_invoice: invoice)
      expect(ticket).not_to be_valid
      expect(ticket.errors[:customer_invoice]).to be_present
    end
  end

  describe "customer timeline" do
    it "logs opened / resolved / closed on the customer's activity timeline, linked to the ticket" do
      ticket = open_ticket
      ticket.change_status!("resolved", by: rep)
      ticket.change_status!("closed", by: manager)

      activities = customer.customer_activities.order(:created_at)
      expect(activities.map(&:activity_type)).to eq(%w[ticket_opened ticket_resolved ticket_closed])
      expect(activities.map(&:ticket_id).uniq).to eq([ticket.id])
      expect(activities.first.note).to eq("T-0001 · Broken kit")
    end
  end

  describe "notifications" do
    it "notifies the assignee on assignment and on someone else's comment, the opener on resolve" do
      ticket = open_ticket(assigned_user: rep_b)
      expect(Notification.where(recipient: rep_b).pluck(Arel.sql("params->>'message_key'"))).to eq(["ticket_assigned"])

      ticket.add_comment!(by: rep_b, body: "on it") # own comment: no notification
      ticket.add_comment!(by: manager, body: "any news?")
      expect(Notification.where(recipient: rep_b).pluck(Arel.sql("params->>'message_key'")))
        .to contain_exactly("ticket_assigned", "ticket_commented")

      ticket.change_status!("resolved", by: rep_b)
      note = Notification.find_by(recipient: rep)
      expect(note.params["message_key"]).to eq("ticket_resolved")
      expect(note.target_path).to eq(Rails.application.routes.url_helpers.admin_sales_ticket_path(ticket))
    end

    it "doesn't notify someone who assigns a ticket to themselves" do
      open_ticket(by: manager, assigned_user: manager)
      expect(Notification.where(recipient: manager)).to be_empty
    end
  end

  describe "visibility (Sales::OwnershipScope#tickets)" do
    it "shows a limited rep tickets on their customers plus ones assigned to or opened by them" do
      other_customer = create(:customer, company: company, name: "Bravo", assigned_user: rep_b)
      mine_by_customer = open_ticket(by: manager)
      assigned_to_me = Ticket.create!(customer: other_customer, opened_by: manager, subject: "a", assigned_user: rep)
      opened_by_me = Ticket.create!(customer: other_customer, opened_by: rep, subject: "b", assigned_user: rep_b)
      hidden = Ticket.create!(customer: other_customer, opened_by: manager, subject: "c", assigned_user: rep_b)

      visible = Sales::OwnershipScope.for(rep).tickets
      expect(visible).to contain_exactly(mine_by_customer, assigned_to_me, opened_by_me)
      expect(Sales::OwnershipScope.for(rep).can_see_ticket?(hidden)).to be(false)
      expect(Sales::OwnershipScope.for(manager).tickets).to include(hidden)
      expect(Sales::OwnershipScope.for(owner).tickets.count).to eq(4)
    end
  end
end
