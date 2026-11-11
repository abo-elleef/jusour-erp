# frozen_string_literal: true

require "rails_helper"

# `completed` and `cancelled` are the only endings an order has, and a completed
# order is only done with once it is paid. A cashier who still owns anything else
# has not finished their shift, whatever the drawer says.
RSpec.describe "Closing a shift over unfinished or unpaid orders", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Front Register", treasury_type: "cash_drawer",
      balance_cents: 50_000, opening_balance_cents: 50_000)
  end

  before do
    Current.company = company
    cashier.update!(assigned_treasury: treasury)
    sign_in cashier
    post open_drawer_pos_shift_path, params: { opening_float: "100.00" }
  end

  def order_for(owner, status: "submitted", with_items: true)
    # The drawer-opening request in `before` resets Current, and the factories read
    # the tenant off it.
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch, status: status)
    if with_items
      create(:order_item, order: order)
      order.recalculate_totals!
    end
    order
  end

  # Paid by card, so the drawer's expected cash does not move.
  def pay!(order)
    Current.company = company
    create(:payment, order: order, amount_cents: order.amount_due_cents, status: "completed",
                     payment_method: "instapay")
    order
  end

  def clock_in!
    Current.company = company
    ShiftLog.create!(user: cashier, clocked_in_at: 1.hour.ago,
      hourly_rate_cents: 1500, status: "active")
  end

  describe "counting down the drawer" do
    it "is refused while an order is still open" do
      order_for(cashier)

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_shift_path(tab: "orders"))
      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.finish_orders_first", count: 1))
      expect(cashier.open_cash_drawer_session(location: branch)).to be_present
    end

    it "is refused over a draft that has food in it" do
      order_for(cashier, status: "draft")

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(flash[:alert]).to be_present
    end

    it "goes through once every order has an ending and is paid" do
      completed = pay!(order_for(cashier))
      cancelled = order_for(cashier)
      Orders::CompleteService.call(completed)
      cancelled.update!(status: "cancelled")

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_shift_path)
      expect(cashier.todays_cash_drawer_session(location: branch).status).to eq("reconciled")
    end

    it "ignores an empty cart — there is nothing in it to finish" do
      order_for(cashier, status: "draft", with_items: false)

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_shift_path)
    end

    it "ignores another cashier's open orders" do
      order_for(other_cashier)

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_shift_path)
    end

    it "is refused over a finished order nobody has paid for, and sends them to collect it" do
      Orders::CompleteService.call(order_for(cashier))

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_orders_path)
      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.collect_payment_first", count: 1))
      expect(cashier.open_cash_drawer_session(location: branch)).to be_present
    end

    it "is refused over a part-paid order" do
      order = order_for(cashier)
      Current.company = company
      create(:payment, order: order, amount_cents: order.amount_due_cents / 2, status: "completed",
                       payment_method: "instapay")
      Orders::CompleteService.call(order)

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.collect_payment_first", count: 1))
    end

    it "ignores another cashier's unpaid orders" do
      Orders::CompleteService.call(order_for(other_cashier))

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_shift_path)
    end
  end

  describe "clocking out" do
    it "is refused while an order is still open" do
      clock_in!
      order_for(cashier)

      patch clock_out_pos_shift_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.finish_orders_first", count: 1))
      expect(cashier.reload).to be_clocked_in
    end

    it "is refused while a finished order is unpaid" do
      clock_in!
      Orders::CompleteService.call(order_for(cashier))

      patch clock_out_pos_shift_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.collect_payment_first", count: 1))
      expect(cashier.reload).to be_clocked_in
    end

    it "goes through once the order is closed and paid" do
      clock_in!
      Orders::CompleteService.call(pay!(order_for(cashier)))

      patch clock_out_pos_shift_path

      expect(cashier.reload).not_to be_clocked_in
    end
  end

  describe "the way out" do
    it "warns on the shift hub, right above the buttons that will refuse" do
      order_for(cashier)

      # An open drawer defaults the page to the orders tab; the close-drawer and
      # clock-out buttons are on the shift tab, which is where the warning belongs.
      get pos_shift_path(tab: "shift")

      expect(response.body).to include(I18n.t("pos.shift.unfinalized_orders_warning", count: 1))
    end

    it "clears the block in one press of Complete all once the money is in" do
      pay!(order_for(cashier))
      pay!(order_for(cashier, status: "draft"))

      post complete_all_pos_orders_path
      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }

      expect(response).to redirect_to(pos_shift_path)
    end
  end
end
