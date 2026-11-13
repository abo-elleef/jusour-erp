# frozen_string_literal: true

require "rails_helper"

# The end-of-service sweep: a stack of tickets whose cash is already in the drawer,
# settled in one press instead of twenty payment modals.
RSpec.describe "Collecting outstanding orders in cash", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:manager) { create(:user, :manager, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Front Register", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0)
  end

  before { Current.company = company }

  def outstanding(order_type: "pickup", total_cents: 5_000, owner: manager)
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch,
                           status: "submitted", order_type: order_type)
    create(:order_item, order: order, quantity: 1, unit_price_cents: total_cents)
    order.recalculate_totals!
    order
  end

  def sign_in_with_drawer(user)
    user.update!(assigned_treasury: treasury)
    sign_in user
    post open_drawer_pos_shift_path, params: { opening_float: "0" }
    Current.company = company
  end

  describe "as a manager with an open drawer" do
    before { sign_in_with_drawer(manager) }

    it "settles every listed order to the penny it still owes" do
      first = outstanding(total_cents: 5_000)
      second = outstanding(total_cents: 3_000)

      post collect_all_cash_pos_orders_path

      expect(first.reload.amount_due_cents).to eq(0)
      expect(second.reload.amount_due_cents).to eq(0)
      expect(flash[:notice]).to eq(
        I18n.t("flash.pos.cash_collected", count: 2, amount: helper_money(8_000))
      )
    end

    it "takes only the remainder of a part-paid order" do
      order = outstanding(total_cents: 5_000)
      create(:payment, order: order, amount_cents: 2_000, status: "completed",
                       payment_method: "instapay")

      post collect_all_cash_pos_orders_path

      cash = order.reload.payments.where(payment_method: "cash").sum(:amount_cents)
      expect(cash).to eq(3_000)
      expect(order.amount_due_cents).to eq(0)
    end

    it "sends a paid draft to the kitchen without completing it" do
      order = outstanding
      order.update!(status: "draft")

      post collect_all_cash_pos_orders_path

      expect(order.reload.status).to eq("submitted")
    end

    it "collects only what the filter is showing" do
      pickup = outstanding(order_type: "pickup")
      delivery = outstanding(order_type: "delivery")
      delivery.update!(delivery_address: "12 Nile St")

      post collect_all_cash_pos_orders_path(order_type: "pickup")

      expect(pickup.reload.amount_due_cents).to eq(0)
      expect(delivery.reload.amount_due_cents).to be_positive
    end

    it "attributes the cash to the collecting user's drawer session" do
      outstanding

      post collect_all_cash_pos_orders_path

      payment = Payment.where(payment_method: "cash").last
      expect(payment.processed_by_user).to eq(manager)
      expect(payment.cash_drawer_session).to eq(manager.open_cash_drawer_session(location: branch))
    end

    it "says so when there is nothing outstanding" do
      post collect_all_cash_pos_orders_path

      expect(flash[:alert]).to eq(I18n.t("flash.pos.nothing_to_collect"))
    end
  end

  it "refuses without an open drawer — the cash has nowhere to land" do
    sign_in manager
    order = outstanding

    post collect_all_cash_pos_orders_path

    expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.no_open_drawer"))
    expect(order.reload.amount_due_cents).to be_positive
  end

  describe "as a cashier with an open drawer" do
    before { sign_in_with_drawer(cashier) }

    it "is offered and settles the cashier's own orders from this shift" do
      order = outstanding(owner: cashier)
      order.update!(status: "completed")

      get pos_orders_path
      expect(response.body).to include(collect_all_cash_pos_orders_path)

      post collect_all_cash_pos_orders_path

      expect(order.reload.amount_due_cents).to eq(0)
      expect(Payment.where(payment_method: "cash").last.cash_drawer_session)
        .to eq(cashier.open_cash_drawer_session(location: branch))
    end

    it "leaves orders from before this shift for one-at-a-time collection" do
      older = outstanding(owner: cashier)
      older.update_columns(created_at: cashier.open_cash_drawer_session(location: branch).created_at - 1.hour)
      current = outstanding(owner: cashier, total_cents: 2_000)

      get pos_orders_path
      expect(response.body).to include(older.order_number.to_s)
      expect(response.body).to include(helper_money(2_000))

      post collect_all_cash_pos_orders_path

      expect(current.reload.amount_due_cents).to eq(0)
      expect(older.reload.amount_due_cents).to be_positive
    end

    it "never touches another cashier's orders" do
      someone_else = outstanding(owner: manager)
      outstanding(owner: cashier)

      post collect_all_cash_pos_orders_path

      expect(someone_else.reload.amount_due_cents).to be_positive
    end

    it "hides the button when only older-shift orders are outstanding" do
      older = outstanding(owner: cashier)
      older.update_columns(created_at: cashier.open_cash_drawer_session(location: branch).created_at - 1.hour)

      get pos_orders_path
      expect(response.body).not_to include(collect_all_cash_pos_orders_path)

      post collect_all_cash_pos_orders_path
      expect(flash[:alert]).to eq(I18n.t("flash.pos.nothing_to_collect"))
      expect(older.reload.amount_due_cents).to be_positive
    end
  end

  def helper_money(cents)
    ApplicationController.helpers.format_money(cents)
  end
end
