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

  def open_drawer_for(user)
    treasury = Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                                balance_cents: 0, opening_balance_cents: 0)
    CashDrawerSession.create!(company: company, user: user, treasury: treasury, location: branch,
                              session_date: BusinessDay.today(location: branch),
                              opening_float_cents: 0, status: "open")
  end

  describe "POST /pos/orders/:id/complete" do
    it "completes an order the cashier marks done" do
      order = open_order

      post complete_pos_order_path(order)

      expect(response).to redirect_to(pos_order_path(order, from: nil))
      expect(order.reload.status).to eq("completed")
    end

    it "completes an order that has not been paid" do
      order = open_order

      post complete_pos_order_path(order)

      expect(order.reload).to be_completed
      expect(order.amount_due_cents).to be_positive
    end

    it "keeps that unpaid order on Collect Payment" do
      order = open_order
      post complete_pos_order_path(order)

      get pos_orders_path
      expect(response.body).to include(order.order_number)
    end

    it "reports an order it cannot move instead of blowing up" do
      order = open_order(status: "draft")
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

    it "offers Mark completed on an open order" do
      order = open_order

      get pos_order_path(order)

      expect(response.body).to include(I18n.t("pos.orders.mark_completed"))
      expect(response.body).to include(complete_pos_order_path(order))
    end

    it "drops it once the order is closed" do
      order = open_order
      post complete_pos_order_path(order)

      get pos_order_path(order, from: "shift")
      expect(response.body).not_to include(complete_pos_order_path(order))
    end

    it "offers the bulk close on the shift screen, counting what it will close" do
      2.times { open_order }

      get pos_shift_path(tab: "orders")

      expect(response.body).to include(complete_all_pos_orders_path)
      expect(response.body).to include(I18n.t("pos.shift.orders.complete_all_confirm", count: 2))
    end

    it "hides the bulk close when nothing is open" do
      get pos_shift_path(tab: "orders")

      expect(response.body).not_to include(complete_all_pos_orders_path)
    end
  end

  describe "POST /pos/orders/complete_all" do
    before { open_drawer_for(cashier) }

    it "closes everything this cashier still has open" do
      mine = [open_order, open_order(status: "ready")]

      post complete_all_pos_orders_path

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
      theirs = open_order(owner: other_cashier)

      post complete_all_pos_orders_path

      expect(theirs.reload.status).to eq("submitted")
    end

    it "says so when there is nothing open" do
      post complete_all_pos_orders_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.no_orders_to_complete"))
    end

    # The bug this covers: two orders missing a table number reported as "no open
    # orders", while the banner above counted them. The cashier had nowhere to go.
    it "distinguishes orders it could not move from having none at all" do
      order = open_order(status: "draft")
      order.update!(order_type: "table", table_number: nil)

      post complete_all_pos_orders_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.orders_not_completable", count: 1))
      expect(flash[:notice]).to be_nil
    end

    it "reports both halves when some close and some cannot" do
      open_order
      blocked = open_order(status: "draft")
      blocked.update!(order_type: "table", table_number: nil)

      post complete_all_pos_orders_path

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
      stale = open_order(status: "draft")
      stale.update!(created_at: 5.days.ago)

      get pos_shift_path(tab: "orders")
      expect(response.body).not_to include(resume_pos_order_path(stale))

      post complete_all_pos_orders_path
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
      order = open_order

      expect {
        post complete_pos_order_path(order)
      }.not_to have_enqueued_job(Printing::PrintReceiptJob)
    end
  end
end
