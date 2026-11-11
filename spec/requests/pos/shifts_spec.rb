# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS shift flow", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:manager) { create(:user, :manager, company: company, pin: "9999") }
  let!(:treasury) do
    Treasury.create!(
      company: company,
      name: "Front Register",
      treasury_type: "cash_drawer",
      balance_cents: 50_000,
      opening_balance_cents: 50_000
    )
  end

  before do
    Current.company = company
    cashier.update!(assigned_treasury: treasury)
    sign_in cashier
  end

  describe "GET /pos/shift" do
    it "shows the shift hub for a cashier" do
      get pos_shift_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pos.shift.title"))
      expect(response.body).to include(I18n.t("pos.shift.tabs.shift"))
      expect(response.body).to include(I18n.t("pos.shift.tabs.orders"))
    end

    # The drawer session is the shift: no order is rung without one. Being
    # clocked in alone is not a window of orders.
    it "lists no orders while clocked in without a drawer" do
      ShiftLog.create!(
        user: cashier,
        clocked_in_at: 2.hours.ago,
        hourly_rate_cents: 1500,
        status: "active"
      )
      order = create(:order, user: cashier, company: company, location: branch, status: "completed",
        subtotal_cents: 1000, tax_cents: 0, total_cents: 1000, created_at: 1.hour.ago)
      create(:order_item, order: order, unit_price_cents: 1000)

      get pos_shift_path(tab: "orders", filter: "all")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pos.shift.orders.no_shift"))
      expect(response.body).not_to include(pos_order_path(order, from: "shift"))
    end

    it "defaults to the open orders and hides finished ones; ?filter=all shows both" do
      CashDrawerSession.create!(user: cashier, treasury: treasury, location: branch,
        session_date: BusinessDay.today(location: branch), opening_float_cents: 0,
        status: "open", created_at: 2.hours.ago)
      done = create(:order, user: cashier, company: company, location: branch, status: "completed",
        subtotal_cents: 1000, tax_cents: 0, total_cents: 1000, created_at: 1.hour.ago)
      create(:order_item, order: done, unit_price_cents: 1000)
      open_order = create(:order, user: cashier, company: company, location: branch, status: "in_progress",
        subtotal_cents: 500, tax_cents: 0, total_cents: 500, created_at: 30.minutes.ago)
      create(:order_item, order: open_order, unit_price_cents: 500)

      get pos_shift_path(tab: "orders")
      expect(response.body).to include(pos_order_path(open_order, from: "shift"))
      expect(response.body).not_to include(pos_order_path(done, from: "shift"))

      get pos_shift_path(tab: "orders", filter: "all")
      expect(response.body).to include(pos_order_path(open_order, from: "shift"))
      expect(response.body).to include(pos_order_path(done, from: "shift"))
    end

    it "lists orders from an open drawer session" do
      CashDrawerSession.create!(
        user: cashier,
        treasury: treasury,
        location: branch,
        session_date: BusinessDay.today(location: branch),
        opening_float_cents: 10_000,
        status: "open",
        created_at: 1.hour.ago
      )
      order = create(:order, user: cashier, company: company, status: "submitted",
        subtotal_cents: 1500, tax_cents: 0, total_cents: 1500, created_at: 30.minutes.ago)
      create(:order_item, order: order, unit_price_cents: 1500)

      get pos_shift_path(tab: "orders")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(order.order_number)
    end

    it "lists today's orders when the cashier has no clock-in or drawer session" do
      order = create(:order, user: cashier, company: company, status: "completed",
        subtotal_cents: 2000, tax_cents: 0, total_cents: 2000, created_at: 2.hours.ago)
      create(:order_item, order: order, unit_price_cents: 2000)
      create(:payment, order: order, amount_cents: 2000)

      get pos_shift_path(tab: "orders")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(order.order_number)
    end
  end

  describe "opening and reconciling a drawer" do
    it "lets the cashier open, count, and reconcile their drawer" do
      post open_drawer_pos_shift_path, params: {
        opening_float: "100.00"
      }
      expect(response).to redirect_to(pos_shift_path)

      session = cashier.reload.open_cash_drawer_session(location: branch)
      expect(session).to be_present
      expect(session.location_id).to eq(branch.id)
      expect(session.session_date).to eq(BusinessDay.today(location: branch))
      expect(session.opening_float_cents).to eq(10_000)

      get count_pos_shift_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pos.shift.sales_summary_title"))
      expect(response.body).to include(I18n.t("pos.shift.count_cash_heading"))

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }
      expect(response).to redirect_to(pos_shift_path)

      session.reload
      expect(session.status).to eq("reconciled")
      expect(session.counted_cash_cents).to eq(10_000)
      expect(session.variance_cents).to eq(0)
    end

    it "requires a manager PIN when variance exceeds the threshold" do
      post open_drawer_pos_shift_path, params: {
        opening_float: "100.00"
      }

      # Counted far enough above the float to trip the gate whatever the threshold
      # is set to, so raising it never quietly turns this test green.
      over_gate = format(
        "%.2f",
        (10_000 + ::Accounting::CashReconciliationService::VARIANCE_ALERT_THRESHOLD_CENTS + 100) / 100.0
      )

      patch reconcile_pos_shift_path, params: { counted_cash: over_gate }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("pos.shift.variance_detected"))

      patch reconcile_pos_shift_path, params: { counted_cash: over_gate, manager_pin: "0000" }
      expect(response).to have_http_status(:unprocessable_entity)

      manager
      patch reconcile_pos_shift_path, params: { counted_cash: over_gate, manager_pin: "9999" }
      expect(response).to redirect_to(pos_shift_path)
      expect(cashier.reload.todays_cash_drawer_session(location: branch).status).to eq("reconciled")
    end
  end
end
