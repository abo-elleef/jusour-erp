# frozen_string_literal: true

require "rails_helper"

# What a cashier does when the customer changes their mind after paying: another
# payment method, another order type or address, or no order at all.
RSpec.describe "Cashier edge cases after payment", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }
  let(:manager) { create(:user, :manager, company: company) }
  let(:treasury) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end

  before { Current.company = company }

  def drawer_for(user, status: "open")
    CashDrawerSession.create!(company: company, user: user, treasury: treasury, location: branch,
                              session_date: BusinessDay.today(location: branch),
                              opening_float_cents: 1_000, status: status)
  end

  def paid_order(drawer:, method: "cash", status: "submitted", owner: cashier)
    order = create(:order, user: owner, company: company, location: branch, status: status)
    create(:order_item, order: order, unit_price_cents: 5_000)
    order.recalculate_totals!
    payment = create(:payment, order: order, amount_cents: order.total_cents, payment_method: method,
                               status: "completed", cash_drawer_session: drawer, processed_by_user: owner)
    [order, payment]
  end

  def summary(drawer)
    Accounting::SessionSalesSummary.for_session(drawer)
  end

  describe "changing the payment method" do
    it "lets a cashier move a cash payment to InstaPay while their drawer is open, and the drawer follows" do
      drawer = drawer_for(cashier)
      order, payment = paid_order(drawer: drawer)
      sign_in cashier

      patch change_payment_method_pos_order_path(order), params: { payment_id: payment.id, payment_method: "instapay" }

      expect(response).to redirect_to(pos_order_path(order, from: nil))
      expect(payment.reload.payment_method).to eq("instapay")
      totals = summary(drawer)
      expect(totals.cash_cents).to eq(0)
      expect(totals.instapay_cents).to eq(order.total_cents)
      expect(totals.expected_cash_cents).to eq(1_000)
    end

    it "shows the change button on the POS order page" do
      drawer = drawer_for(cashier)
      order, = paid_order(drawer: drawer)
      sign_in cashier

      get pos_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(change_payment_method_pos_order_path(order))
    end

    it "shows the change button on the admin order page only while the drawer is open" do
      drawer = drawer_for(cashier)
      order, = paid_order(drawer: drawer)
      sign_in manager

      get admin_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(change_payment_method_admin_order_path(order))

      drawer.update!(status: "reconciled")
      get admin_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(change_payment_method_admin_order_path(order))
    end

    it "refuses once the drawer is closed, even for a manager" do
      drawer = drawer_for(cashier, status: "reconciled")
      order, payment = paid_order(drawer: drawer)
      sign_in manager

      patch change_payment_method_admin_order_path(order), params: { payment_id: payment.id, payment_method: "instapay" }

      expect(payment.reload.payment_method).to eq("cash")
      expect(flash[:alert]).to eq(I18n.t("flash.pos.payment_method_change_errors.drawer_closed"))
    end

    it "refuses a cashier changing another cashier's drawer, but lets a manager do it" do
      drawer = drawer_for(other_cashier)
      order, payment = paid_order(drawer: drawer, owner: other_cashier)

      sign_in cashier
      patch change_payment_method_pos_order_path(order), params: { payment_id: payment.id, payment_method: "vodafone_cash" }
      expect(payment.reload.payment_method).to eq("cash")

      sign_in manager
      patch change_payment_method_admin_order_path(order), params: { payment_id: payment.id, payment_method: "vodafone_cash" }
      expect(payment.reload.payment_method).to eq("vodafone_cash")
    end

    it "refuses methods the drawer does not account for" do
      drawer = drawer_for(cashier)
      order, payment = paid_order(drawer: drawer)
      sign_in cashier

      patch change_payment_method_pos_order_path(order), params: { payment_id: payment.id, payment_method: "staff_deduction" }

      expect(payment.reload.payment_method).to eq("cash")
    end
  end

  describe "changing order type and address on a paid order" do
    it "switches pickup to delivery without crashing" do
      customer = create(:customer, company: company)
      order, = paid_order(drawer: drawer_for(cashier), status: "submitted")
      order.update!(order_type: "pickup", customer: customer)
      sign_in cashier

      patch update_fulfillment_pos_order_path(order), params: { order_type: "delivery", delivery_address: "12 Nile St" }

      expect(response).to redirect_to(pos_order_path(order, from: nil))
      expect(order.reload.order_type).to eq("delivery")
      expect(order.delivery_address).to eq("12 Nile St")
    end

    it "switches delivery to dine-in with a table" do
      order, = paid_order(drawer: drawer_for(cashier), status: "ready")
      sign_in cashier

      patch update_fulfillment_pos_order_path(order), params: { order_type: "table", table_number: "4" }

      expect(order.reload.order_type).to eq("table")
      expect(order.table_number).to eq("4")
    end
  end

  describe "voiding a paid order" do
    it "cancels it and refunds the money, so the drawer no longer expects it" do
      drawer = drawer_for(cashier)
      order, payment = paid_order(drawer: drawer)
      sign_in manager

      post void_admin_order_path(order), params: { reason: "Customer left" }

      expect(order.reload).to be_cancelled
      expect(payment.reload.status).to eq("refunded")
      expect(payment.refunded_amount_cents).to eq(order.total_cents)
      expect(summary(drawer).expected_cash_cents).to eq(1_000)
    end

    it "voids an order that is already ready on the pass" do
      order, = paid_order(drawer: drawer_for(cashier), status: "ready")
      sign_in manager

      post void_admin_order_path(order)

      expect(order.reload).to be_cancelled
    end

    it "does not void the same order twice" do
      order, = paid_order(drawer: drawer_for(cashier), status: "cancelled")
      sign_in manager

      post void_admin_order_path(order)

      expect(order.order_events.where(event_type: "void")).to be_empty
    end
  end

  describe "refunding a completed order" do
    it "keeps the part the customer did not get back in the drawer" do
      drawer = drawer_for(cashier)
      order, payment = paid_order(drawer: drawer, status: "completed")
      sign_in manager

      post refund_admin_order_path(order), params: { amount_pounds: "10", reason: "Cold fries" }

      expect(payment.reload.status).to eq("partially_refunded")
      expect(summary(drawer).cash_cents).to eq(order.total_cents - 1_000)
      expect(summary(drawer).expected_cash_cents).to eq(1_000 + order.total_cents - 1_000)
    end

    it "refuses more than was paid" do
      order, payment = paid_order(drawer: drawer_for(cashier), status: "completed")
      sign_in manager

      post refund_admin_order_path(order), params: { amount_pounds: "999999", reason: "Typo" }

      expect(payment.reload.status).to eq("completed")
      expect(order.order_events.where(event_type: "refund")).to be_empty
    end
  end
end
