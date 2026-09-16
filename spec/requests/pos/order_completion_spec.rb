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
      expect(response.body).to include(I18n.t("pos.shift.orders.open_count", count: 2))
    end

    it "hides the bulk close when nothing is open" do
      get pos_shift_path(tab: "orders")

      expect(response.body).not_to include(complete_all_pos_orders_path)
    end
  end

  describe "POST /pos/orders/complete_all" do
    it "closes everything this cashier still has open" do
      mine = [open_order, open_order(status: "ready")]

      post complete_all_pos_orders_path

      expect(response).to redirect_to(pos_shift_path(tab: "orders"))
      expect(mine.map { |o| o.reload.status }).to all(eq("completed"))
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
  end

  describe "the receipt" do
    it "prints when the order is paid off, not when it is completed" do
      order = open_order

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
