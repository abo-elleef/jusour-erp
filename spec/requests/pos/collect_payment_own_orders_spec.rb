# frozen_string_literal: true

require "rails_helper"

# Collect Payment lists only the signed-in user's own unpaid orders. Each cashier
# collects on their own orders before their shift can close, so nobody needs to
# see — or sweep — anyone else's.
RSpec.describe "Collect Payment: own orders only", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }
  let(:manager) { create(:user, :manager, company: company) }

  before { Current.company = company }

  def unpaid_order(owner, status: "submitted")
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch, status: status)
    create(:order_item, order: order, quantity: 1, unit_price_cents: 5_000)
    order.recalculate_totals!
    order
  end

  # The Pay link, matched with its closing quote so order 1 never matches order 12.
  def pay_link(order)
    %(href="#{pos_order_path(order)}")
  end

  it "shows a cashier their own unpaid orders and no one else's" do
    sign_in cashier
    mine = unpaid_order(cashier)
    theirs = unpaid_order(other_cashier)
    their_finished = unpaid_order(other_cashier, status: "completed")

    get pos_orders_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(pay_link(mine))
    expect(response.body).not_to include(pay_link(theirs))
    expect(response.body).not_to include(pay_link(their_finished))
  end

  it "keeps the filter to their own orders within an order type" do
    sign_in cashier
    mine = unpaid_order(cashier)
    theirs = unpaid_order(other_cashier)

    get pos_orders_path(order_type: "pickup")

    expect(response.body).to include(pay_link(mine))
    expect(response.body).not_to include(pay_link(theirs))
  end

  it "gives a manager on the register the same own-orders list" do
    sign_in manager
    own = unpaid_order(manager)
    cashiers = unpaid_order(cashier)

    get pos_orders_path

    expect(response.body).to include(pay_link(own))
    expect(response.body).not_to include(pay_link(cashiers))
  end

  it "collects in cash only the manager's own orders" do
    treasury = Treasury.create!(company: company, name: "Front Register", treasury_type: "cash_drawer",
                                balance_cents: 0, opening_balance_cents: 0)
    manager.update!(assigned_treasury: treasury)
    sign_in manager
    post open_drawer_pos_shift_path, params: { opening_float: "0" }
    own = unpaid_order(manager)
    cashiers = unpaid_order(cashier)

    post collect_all_cash_pos_orders_path

    expect(own.reload.amount_due_cents).to eq(0)
    expect(cashiers.reload.amount_due_cents).to be_positive
  end
end
