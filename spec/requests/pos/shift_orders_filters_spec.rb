# frozen_string_literal: true

require "rails_helper"

# My Shift → Orders: narrow the list by order type and payment method, and add up
# what is shown (cancelled orders listed but not counted). Delivery fee has its own column.
RSpec.describe "Shift orders filters and total", type: :request do
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
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.new(2026, 6, 10), opening_float_cents: 0, status: "open",
                              created_at: Time.zone.local(2026, 6, 10, 12, 0, 0))
    sign_in cashier
  end

  def order(type:, method:, status: "completed", delivery_fee_cents: 0)
    Current.company = company
    o = create(:order, user: cashier, company: company, location: branch, status: status,
                       order_type: type, created_at: Time.zone.local(2026, 6, 10, 13, 0, 0))
    create(:order_item, order: o)
    o.update!(delivery_fee_cents: delivery_fee_cents)
    o.recalculate_totals!
    create(:payment, order: o, payment_method: method, amount_cents: o.total_cents)
    o.reload
  end

  def listed?(o) = response.body.include?(pos_order_path(o, from: "shift"))

  def footer_total
    Nokogiri::HTML(response.body).at_css("[data-testid='shift-orders-total']")&.text&.strip
  end

  def footer_delivery_fee
    Nokogiri::HTML(response.body).at_css("[data-testid='shift-orders-delivery-fee-total']")&.text&.strip
  end

  let!(:cash_pickup) { order(type: "pickup", method: "cash") }
  let!(:card_delivery) { order(type: "delivery", method: "card", delivery_fee_cents: 2500) }
  let!(:cash_delivery) { order(type: "delivery", method: "cash", delivery_fee_cents: 1500) }
  let!(:cancelled_cash_delivery) { order(type: "delivery", method: "cash", status: "cancelled", delivery_fee_cents: 900) }

  it "filters by order type" do
    get pos_shift_path(tab: "orders", filter: "all", order_type: "delivery")

    expect(listed?(card_delivery)).to be(true)
    expect(listed?(cash_delivery)).to be(true)
    expect(listed?(cash_pickup)).to be(false)
  end

  it "filters by payment method" do
    get pos_shift_path(tab: "orders", filter: "all", payment_method: "card")

    expect(listed?(card_delivery)).to be(true)
    expect(listed?(cash_pickup)).to be(false)
    expect(listed?(cash_delivery)).to be(false)
  end

  it "totals the filtered orders and their delivery fees, leaving out cancelled ones" do
    get pos_shift_path(tab: "orders", filter: "all", order_type: "delivery", payment_method: "cash")

    expect(listed?(cash_delivery)).to be(true)
    expect(listed?(cancelled_cash_delivery)).to be(true)
    expect(listed?(card_delivery)).to be(false)
    view = ApplicationController.helpers
    expect(footer_total).to eq(view.format_money(cash_delivery.total_cents))
    expect(footer_delivery_fee).to eq(view.format_money(1500))
  end

  it "ignores unknown filter values" do
    get pos_shift_path(tab: "orders", filter: "all", order_type: "bogus", payment_method: "bitcoin")

    expect(response).to have_http_status(:ok)
    expect(listed?(cash_pickup)).to be(true)
    expect(listed?(card_delivery)).to be(true)
  end
end
