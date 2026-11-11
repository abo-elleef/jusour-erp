# frozen_string_literal: true

require "rails_helper"

# Restaurant delivery fees vary order to order, so the cashier types the fee in
# the payment modal and it is added to what the customer owes.
RSpec.describe "Delivery fee on POS orders", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let(:order_type) { "delivery" }
  let(:order) do
    o = create(:order, user: cashier, company: company, location: branch, status: "draft", order_type: order_type,
                         delivery_address: "12 Nile St")
    create(:order_item, order: o)
    o.recalculate_totals!
    o
  end
  let!(:food_total) { order.total_cents }

  before do
    Current.company = company
    CashDrawerSession.create!(
      company: company, user: cashier, treasury: treasury, location: branch,
      session_date: BusinessDay.today(location: branch), opening_float_cents: 0, status: "open"
    )
    sign_in cashier
  end

  def pay(amount_cents:, fee: nil, method: "cash")
    params = { order_id: order.id, payment_method: method, amount_pounds: (amount_cents / 100.0).to_s }
    params[:delivery_fee_pounds] = fee unless fee.nil?
    post pos_payments_path, params: params
  end

  it "adds the fee to the total and settles the order when the whole amount is paid" do
    pay(amount_cents: food_total + 2_500, fee: "25")

    order.reload
    expect(order.delivery_fee_cents).to eq(2_500)
    expect(order.total_cents).to eq(food_total + 2_500)
    expect(order).to be_fully_paid
    expect(order.status).to eq("submitted")
  end

  it "records the fee as paid out of the cashier's drawer" do
    pay(amount_cents: food_total + 2_500, fee: "25")

    drawer = cashier.open_cash_drawer_session(location: branch)
    expect(order.reload.delivery_fee_drawer_session).to eq(drawer)
    expect(Accounting::SessionSalesSummary.for_session(drawer).expected_cash_cents).to eq(food_total)
  end

  it "leaves the order owing the fee when only the food is paid" do
    pay(amount_cents: food_total, fee: "25")

    order.reload
    expect(order).not_to be_fully_paid
    expect(order.amount_due_cents).to eq(2_500)
  end

  it "works with InstaPay too" do
    pay(amount_cents: food_total + 1_050, fee: "10.5", method: "instapay")

    expect(order.reload.delivery_fee_cents).to eq(1_050)
    expect(order).to be_fully_paid
  end

  it "treats a blank fee as free delivery" do
    pay(amount_cents: food_total, fee: "")

    expect(order.reload.delivery_fee_cents).to eq(0)
    expect(order).to be_fully_paid
  end

  it "refuses a negative fee and takes no payment" do
    expect { pay(amount_cents: food_total, fee: "-5") }.not_to change(Payment, :count)
    expect(order.reload.delivery_fee_cents).to eq(0)
    expect(flash[:alert]).to be_present
  end

  it "keeps the fee set by the first payment when a later payment sends another" do
    pay(amount_cents: 1_000, fee: "25")
    pay(amount_cents: food_total + 2_500 - 1_000, fee: "40")

    order.reload
    expect(order.delivery_fee_cents).to eq(2_500)
    expect(order).to be_fully_paid
  end

  context "when the order is not a delivery" do
    let(:order_type) { "pickup" }

    it "ignores the fee" do
      pay(amount_cents: food_total, fee: "25")

      expect(order.reload.delivery_fee_cents).to eq(0)
      expect(order).to be_fully_paid
    end
  end

  describe "the payment modal" do
    it "asks for the fee on a delivery order" do
      get pos_order_path(order)
      expect(response.body).to include('data-payment-target="deliveryFee"')
    end

    context "for a pickup order" do
      let(:order_type) { "pickup" }

      it "does not ask for a fee" do
        get pos_order_path(order)
        expect(response.body).not_to include('data-payment-target="deliveryFee"')
      end
    end
  end
end
