# frozen_string_literal: true

require "rails_helper"

# Closing an order is now a cashier's explicit act. These cover the two ways they
# can do it, and the one thing that must not have moved with it — the customer's
# receipt, which follows the money rather than the status.
RSpec.describe "POS order completion", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }

  before do
    Current.company = company
    sign_in cashier
  end

  def open_order(owner: cashier, status: "submitted")
    order = create(:order, user: owner, company: company, location: branch, status: status)
    create(:order_item, order: order)
    order.recalculate_totals!
    order
  end

  def paid_open_order(owner: cashier, status: "submitted")
    order = open_order(owner: owner, status: status)
    create(:payment, order: order, amount_cents: order.total_cents)
    order
  end

  def open_drawer_for(user)
    treasury = Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                                balance_cents: 0, opening_balance_cents: 0)
    CashDrawerSession.create!(company: company, user: user, treasury: treasury, location: branch,
                              session_date: BusinessDay.today(location: branch),
                              opening_float_cents: 0, status: "open")
  end

  describe "POST /pos/orders/:id/complete" do
    it "completes an order the cashier marks done" do
      order = paid_open_order

      post complete_pos_order_path(order)

      expect(response).to redirect_to(pos_order_path(order, from: nil))
      expect(order.reload.status).to eq("completed")
    end

    # Cashiers complete paid orders only; handing over now and collecting later is
    # a manager's call (orders:complete_unpaid).
    it "refuses a cashier completing an order that has not been paid" do
      order = open_order

      post complete_pos_order_path(order)

      expect(flash[:alert]).to eq(I18n.t("flash.unauthorized"))
      expect(order.reload.status).to eq("submitted")
    end

    it "refuses a part-paid order too" do
      order = open_order
      create(:payment, order: order, amount_cents: order.total_cents - 1)

      post complete_pos_order_path(order)

      expect(order.reload.status).to eq("submitted")
    end

    context "as a manager" do
      let(:manager) { create(:user, company: company, role: "manager") }

      before { sign_in manager }

      it "completes an order that has not been paid" do
        order = open_order

        post complete_pos_order_path(order)

        expect(order.reload).to be_completed
        expect(order.amount_due_cents).to be_positive
      end

      it "keeps that unpaid order on Collect Payment" do
        order = open_order(owner: manager)
        post complete_pos_order_path(order)

        get pos_orders_path
        expect(response.body).to include(order.order_number)
      end
    end

    it "lets a cashier role given orders:complete_unpaid complete an unpaid order" do
      role = Role.find_or_create_by!(company: company, key: "cashier") { |r| r.name = "Cashier" }
      role.update!(permissions: %w[pos:access orders:complete_unpaid])
      cashier.update!(role_id: role.id)
      order = open_order

      post complete_pos_order_path(order)

      expect(order.reload).to be_completed
    end

    it "goes back to the My Shift list a row's Complete came from" do
      order = paid_open_order
      back = pos_shift_path(tab: "orders", filter: "open")

      post complete_pos_order_path(order, from: "shift", return_to: back)

      expect(response).to redirect_to(back)
      expect(order.reload).to be_completed
    end

    it "ignores a return_to that is not the My Shift page" do
      order = paid_open_order

      post complete_pos_order_path(order, from: "shift", return_to: "https://evil.example/pos/shift")

      expect(response).to redirect_to(pos_order_path(order, from: "shift"))
    end

    it "reports an order it cannot move instead of blowing up" do
      order = paid_open_order(status: "draft")
      order.update!(order_type: "table", table_number: nil)

      post complete_pos_order_path(order)

      expect(flash[:alert]).to eq(I18n.t("flash.pos.order_not_completable"))
      expect(order.reload.status).to eq("draft")
    end
  end

  # Asserted on the form action rather than the label: the Arabic flash for a
  # completed order contains the button's own text, so matching on words would
  # pass whether or not the button is there.
  describe "the buttons that reach those actions" do
    before { open_drawer_for(cashier) }

    it "offers Mark completed on a paid open order" do
      order = paid_open_order

      get pos_order_path(order)

      expect(response.body).to include(I18n.t("pos.orders.mark_completed"))
      expect(response.body).to include(complete_pos_order_path(order))
    end

    it "greys out Mark completed on an unpaid order and says why" do
      order = open_order

      get pos_order_path(order)

      expect(response.body).not_to include(complete_pos_order_path(order))
      expect(response.body).to include('data-testid="complete-needs-payment"')
    end

    it "offers Complete on a paid row of My Shift, not on an unpaid one" do
      paid = paid_open_order
      unpaid = open_order

      get pos_shift_path(tab: "orders", filter: "open")

      expect(response.body).to include(complete_pos_order_path(paid, from: "shift"))
      expect(response.body).not_to include(complete_pos_order_path(unpaid, from: "shift"))
    end

    it "badges the nav with paid-to-complete and placed-unpaid counts" do
      3.times { paid_open_order }
      2.times { open_order }
      open_order(status: "draft") # a cart still being rung up is not counted

      get pos_shift_path(tab: "orders")

      expect(response.body).to match(/data-testid="pos-nudge-paid-to-complete"[^>]*>\s*3\s*</)
      expect(response.body).to match(/data-testid="pos-nudge-unpaid"[^>]*>\s*2\s*</)
    end

    it "turns a badge red and pulsing once the backlog is large" do
      10.times { open_order }

      get pos_shift_path(tab: "orders")

      expect(response.body).to match(/data-testid="pos-nudge-unpaid"[^>]*class="[^"]*bg-rose-600[^"]*motion-safe:animate-pulse/)
      expect(response.body).not_to match(/data-testid="pos-nudge-paid-to-complete"/)
    end

    it "shows no badges when nothing is waiting" do
      get pos_shift_path(tab: "orders")

      expect(response.body).not_to include("pos-nudge-")
    end

    it "drops it once the order is closed" do
      order = paid_open_order
      post complete_pos_order_path(order)

      get pos_order_path(order, from: "shift")
      expect(response.body).not_to include(complete_pos_order_path(order))
    end

    it "offers the bulk close for paid orders only, counting what it will close" do
      2.times { paid_open_order }
      open_order

      get pos_shift_path(tab: "orders")

      expect(response.body).to include(complete_paid_pos_orders_path)
      expect(response.body).to include(I18n.t("pos.shift.orders.complete_paid_confirm", count: 2))
    end

    it "hides the bulk close when no open order is paid" do
      open_order

      get pos_shift_path(tab: "orders")

      expect(response.body).not_to include(complete_paid_pos_orders_path)
    end

    it "no longer offers a way to complete unpaid orders in bulk" do
      post "/pos/orders/complete_all"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /pos/orders/complete_paid" do
    before { open_drawer_for(cashier) }

    it "closes every paid order this cashier still has open" do
      mine = [paid_open_order, paid_open_order(status: "ready")]

      post complete_paid_pos_orders_path

      expect(response).to redirect_to(pos_shift_path(tab: "orders"))
      expect(mine.map { |o| o.reload.status }).to all(eq("completed"))
    end

    it "complete_paid closes only the fully paid open orders" do
      paid = open_order
      create(:payment, order: paid, amount_cents: paid.total_cents)
      part = open_order
      create(:payment, order: part, amount_cents: part.total_cents - 1)
      unpaid = open_order

      post complete_paid_pos_orders_path

      expect(response).to redirect_to(pos_shift_path(tab: "orders"))
      expect(paid.reload.status).to eq("completed")
      expect(part.reload.status).to eq("submitted")
      expect(unpaid.reload.status).to eq("submitted")
    end

    it "leaves another cashier's orders alone" do
      theirs = paid_open_order(owner: other_cashier)

      post complete_paid_pos_orders_path

      expect(theirs.reload.status).to eq("submitted")
    end

    it "says so when there is nothing open" do
      post complete_paid_pos_orders_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.no_orders_to_complete"))
    end

    # The bug this covers: two orders missing a table number reported as "no open
    # orders", while the banner above counted them. The cashier had nowhere to go.
    it "distinguishes orders it could not move from having none at all" do
      order = paid_open_order(status: "draft")
      order.update!(order_type: "table", table_number: nil)

      post complete_paid_pos_orders_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.orders_not_completable", count: 1))
      expect(flash[:notice]).to be_nil
    end

    it "reports both halves when some close and some cannot" do
      paid_open_order
      blocked = paid_open_order(status: "draft")
      blocked.update!(order_type: "table", table_number: nil)

      post complete_paid_pos_orders_path

      expect(flash[:notice]).to eq(I18n.t("flash.pos.orders_completed", count: 1))
      expect(flash[:alert]).to eq(I18n.t("flash.pos.orders_not_completable", count: 1))
    end

    it "gives both shift tabs the full width" do
      %w[orders shift].each do |tab|
        get pos_shift_path(tab: tab)
        expect(response.body).not_to include("p-5 max-w-2xl mx-auto")
      end
    end

    # The cashier works their current drawer session only. An order left open in
    # an earlier one is the admin's to handle, so it is neither listed nor closed.
    it "leaves an unfinished order from an earlier session out of the list and the bulk close" do
      stale = paid_open_order(status: "draft")
      stale.update!(created_at: 5.days.ago)

      get pos_shift_path(tab: "orders")
      expect(response.body).not_to include(resume_pos_order_path(stale))

      post complete_paid_pos_orders_path
      expect(stale.reload.status).to eq("draft")
    end
  end

  describe "the receipt" do
    # Paid straight from the cart: the payment places the order and prints. (An
    # order placed earlier printed then; its payment prints nothing.)
    it "prints when a cart is paid off, not when it is completed" do
      order = open_order(status: "draft")
      open_drawer_for(cashier)

      expect {
        post pos_payments_path, params: {
          order_id: order.id, payment_method: "cash",
          amount_pounds: (order.total_cents / 100.0).to_s
        }
      }.to have_enqueued_job(Printing::PrintReceiptJob).with(order.id)

      expect(order.reload.status).to eq("submitted")
    end

    it "is not printed a second time when the cashier closes the order" do
      order = paid_open_order

      expect {
        post complete_pos_order_path(order)
      }.not_to have_enqueued_job(Printing::PrintReceiptJob)
    end
  end
end
