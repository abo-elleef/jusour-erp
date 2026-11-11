# frozen_string_literal: true

require "rails_helper"

# No order is rung without an open drawer, so the drawer session is the cashier's
# shift. The orders tab, the close guard and Complete all look at that session
# only; orders left over from an earlier session are the admin's to handle.
RSpec.describe "Shift orders tab shows the current drawer session", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 15, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end

  before do
    Current.company = company
    cashier.update!(assigned_treasury: till)
    sign_in cashier
  end

  def drawer(opened_at:, date:, status: "open", closed_at: nil)
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: date, opening_float_cents: 0, status: status,
                              created_at: opened_at, updated_at: closed_at || opened_at)
  end

  def order_at(time, owner: cashier, status: "completed")
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch, status: status, created_at: time)
    create(:order_item, order: order)
    order.recalculate_totals!
    order
  end

  def listed?(order)
    # By link, not number: order numbers restart every day, so yesterday's #1 and
    # today's #1 print the same.
    response.body.include?(pos_order_path(order, from: "shift"))
  end

  let!(:yesterdays_drawer) do
    drawer(opened_at: Time.zone.local(2026, 6, 9, 10, 0, 0), date: Date.new(2026, 6, 9),
           status: "reconciled", closed_at: Time.zone.local(2026, 6, 9, 22, 0, 0))
  end
  let!(:todays_drawer) { drawer(opened_at: Time.zone.local(2026, 6, 10, 12, 0, 0), date: Date.new(2026, 6, 10)) }

  it "lists this session's orders and leaves out yesterday's and other cashiers'" do
    mine = order_at(Time.zone.local(2026, 6, 10, 13, 0, 0))
    yesterday = order_at(Time.zone.local(2026, 6, 9, 12, 0, 0))
    theirs = order_at(Time.zone.local(2026, 6, 10, 13, 0, 0), owner: create(:user, company: company, role: "cashier"))

    get pos_shift_path(tab: "orders", filter: "all")

    expect(listed?(mine)).to be(true)
    expect(listed?(yesterday)).to be(false)
    expect(listed?(theirs)).to be(false)
  end

  it "does not show an order left open in an earlier session" do
    stale = order_at(Time.zone.local(2026, 6, 9, 12, 0, 0), status: "submitted")
    current = order_at(Time.zone.local(2026, 6, 10, 13, 0, 0), status: "submitted")

    get pos_shift_path(tab: "orders", filter: "open")

    expect(listed?(current)).to be(true)
    expect(listed?(stale)).to be(false)
  end

  it "does not let an earlier session's open order block closing the drawer" do
    order_at(Time.zone.local(2026, 6, 9, 12, 0, 0), status: "submitted")

    patch reconcile_pos_shift_path, params: { counted_cash: "0" }

    expect(response).to redirect_to(pos_shift_path)
    expect(todays_drawer.reload.status).to eq("reconciled")
  end

  it "leaves an earlier session's open order alone on Complete all" do
    stale = order_at(Time.zone.local(2026, 6, 9, 12, 0, 0), status: "submitted")
    current = order_at(Time.zone.local(2026, 6, 10, 13, 0, 0), status: "submitted")

    post complete_all_pos_orders_path

    expect(current.reload.status).to eq("completed")
    expect(stale.reload.status).to eq("submitted")
  end
end
