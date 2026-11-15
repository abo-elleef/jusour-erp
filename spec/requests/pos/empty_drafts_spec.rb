# frozen_string_literal: true

require "rails_helper"

# The register saves a cart as soon as the cashier attaches a customer, picks a
# type or writes a note, before any item. A cart left that way used to stay a
# draft forever and fill the shift list with 0-item orders. It is now deleted
# when the cashier moves on, at drawer close and by the nightly sweep.
RSpec.describe "Empty draft carts", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch", table_service: true, table_count: 6) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }

  before do
    Current.company = company
    sign_in cashier
    open_drawer_for(cashier, location: branch)
  end

  # Writing a note saves the cart without an item, like the register does.
  def start_empty_cart!
    patch pos_update_notes_path, params: { notes: "no onions" }
    Current.company = company
    Order.order(:id).last
  end

  def draft(owner: cashier, items: 0)
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch, status: "draft")
    items.times { create(:order_item, order: order) }
    order.recalculate_totals! if items.positive?
    order
  end

  describe "opening the add popup" do
    it "does not save a cart, so a cancelled popup leaves nothing behind" do
      Current.company = company
      item = create(:menu_item, company: company, name: "Old School", base_price_cents: 10_000)
      create(:location_menu_item, location: branch, menu_item: item, available: true)

      expect { get pos_modifier_form_path(menu_item_id: item.id) }.not_to change(Order, :count)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Old School")
    end
  end

  describe "moving on from the cart" do
    it "deletes the empty cart on New order" do
      cart = start_empty_cart!
      expect(cart).to be_present

      expect { post pos_new_order_path }.to change(Order, :count).by(-1)
      expect(Order.exists?(cart.id)).to be(false)
      expect(AuditLogEntry.where(action: "order.discard_empty", record_id: cart.id)).to exist
    end

    it "keeps a cart with an item on New order" do
      cart = start_empty_cart!
      Current.company = company
      create(:order_item, order: cart)

      expect { post pos_new_order_path }.not_to change(Order, :count)
    end

    it "deletes the cart whose last item was removed" do
      cart = start_empty_cart!
      Current.company = company
      item = create(:order_item, order: cart)
      delete pos_order_item_path(item)

      expect { post pos_new_order_path }.to change(Order, :count).by(-1)
    end

    it "deletes the empty cart when another order is resumed, and keeps the resumed one" do
      cart = start_empty_cart!
      other = draft(items: 1)

      post resume_pos_order_path(other)

      expect(Order.exists?(cart.id)).to be(false)
      expect(Order.exists?(other.id)).to be(true)
    end

    it "deletes the empty cart when a table is opened" do
      cart = start_empty_cart!

      post pos_open_table_path(number: "4")

      expect(Order.exists?(cart.id)).to be(false)
      expect(Order.where(table_number: "4")).to exist
    end

    it "never touches another cashier's empty draft" do
      theirs = draft(owner: other_cashier)
      start_empty_cart!

      post pos_new_order_path

      expect(Order.exists?(theirs.id)).to be(true)
    end
  end

  describe "closing the drawer" do
    it "deletes this cashier's empty drafts and keeps everyone else's" do
      mine = draft
      theirs = draft(owner: other_cashier)

      patch reconcile_pos_shift_path, params: { counted_cash: "0" }

      expect(response).to redirect_to(pos_shift_path)
      expect(Order.exists?(mine.id)).to be(false)
      expect(Order.exists?(theirs.id)).to be(true)
    end
  end

  describe "the cashier's lists" do
    it "leaves empty drafts out of the shift's orders tab" do
      empty = draft
      full = draft(items: 1)

      get pos_shift_path(tab: "orders", filter: "all")

      expect(response.body).to include(pos_order_path(full))
      expect(response.body).not_to include(pos_order_path(empty))
    end
  end

  describe "the admin orders page" do
    let(:owner) { create(:user, company: company, role: "owner") }

    it "lists an empty draft dimmed with an Empty label" do
      draft
      sign_in owner

      get admin_orders_path

      expect(response.body).to include("opacity-50")
      expect(response.body).to include(I18n.t("admin.orders.empty_draft"))
    end
  end

  describe "orders:discard_empty_drafts" do
    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("orders:discard_empty_drafts")
      Rake::Task["orders:discard_empty_drafts"].reenable
    end

    it "deletes empty drafts older than 24 hours only" do
      old = draft.tap { |o| o.update_columns(created_at: 25.hours.ago) }
      fresh = draft.tap { |o| o.update_columns(created_at: 23.hours.ago) }
      full = draft(items: 1).tap { |o| o.update_columns(created_at: 2.days.ago) }

      expect { Rake::Task["orders:discard_empty_drafts"].invoke }.to output(/1 empty draft/).to_stdout

      Current.company = company
      expect(Order.exists?(old.id)).to be(false)
      expect(Order.exists?(fresh.id)).to be(true)
      expect(Order.exists?(full.id)).to be(true)
    end
  end
end
