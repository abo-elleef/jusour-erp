# frozen_string_literal: true

require "rails_helper"

# A cart is not a record of anything until money touches it, so a cashier can throw
# their own away. Everything else is history and gets voided by a manager instead.
RSpec.describe "Discarding a draft cart", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier") }

  before do
    Current.company = company
    sign_in cashier
  end

  def cart(owner: cashier, status: "draft")
    Current.company = company
    order = create(:order, user: owner, company: company, location: branch, status: status)
    create(:order_item, order: order)
    order.recalculate_totals!
    order
  end

  it "deletes the cashier's own draft, and its items with it" do
    order = cart

    expect { delete pos_order_path(order) }
      .to change(Order, :count).by(-1)
      .and change(OrderItem, :count).by(-1)

    expect(flash[:notice]).to eq(I18n.t("flash.pos.order_discarded", number: order.order_number))
  end

  it "offers the button on the shift screen" do
    till = Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                            balance_cents: 0, opening_balance_cents: 0)
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: BusinessDay.today(location: branch),
                              opening_float_cents: 0, status: "open")
    order = cart
    get pos_shift_path(tab: "orders")
    expect(response.body).to include(pos_order_path(order))
  end

  it "refuses a draft that has taken money" do
    order = cart
    create(:payment, order: order, amount_cents: 500, status: "completed")

    expect { delete pos_order_path(order) }.not_to change(Order, :count)
  end

  it "refuses another cashier's cart" do
    order = cart(owner: other_cashier)

    expect { delete pos_order_path(order) }.not_to change(Order, :count)
  end

  it "refuses anything that has left draft" do
    order = cart(status: "submitted")

    expect { delete pos_order_path(order) }.not_to change(Order, :count)
  end

  it "hides the button for an order it would refuse" do
    order = cart(status: "submitted")
    get pos_shift_path(tab: "orders")
    expect(response.body).not_to include("\"#{pos_order_path(order)}\"")
  end

  it "clears the cart from the session if it was the live one" do
    order = cart
    post pos_order_items_path, params: { menu_item_id: create(:menu_item, company: company).id }

    delete pos_order_path(order)
    expect(Order.where(id: order.id)).to be_empty
  end
end
