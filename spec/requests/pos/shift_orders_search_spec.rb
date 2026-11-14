# frozen_string_literal: true

require "rails_helper"

# My Shift → Orders: one search box (order/table number, offline number, customer
# name/phone/email, notes, address, item name), the offline number column, and
# sorting by customer, payment method and offline number.
RSpec.describe "Shift orders search, offline number and sorting", type: :request do
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
  let(:mona) { create(:customer, company: company, name: "Mona Adel", phone: "01011112222") }
  let(:zain) { create(:customer, company: company, name: "Zain Ali", phone: "01233334444") }

  before do
    Current.company = company
    cashier.update!(assigned_treasury: till)
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.new(2026, 6, 10), opening_float_cents: 0, status: "open",
                              created_at: Time.zone.local(2026, 6, 10, 12, 0, 0))
    sign_in cashier
  end

  def order(number:, customer: nil, method: "cash", **attrs)
    Current.company = company
    o = create(:order, user: cashier, company: company, location: branch, status: "completed",
                       order_type: "pickup", customer: customer, created_at: Time.zone.local(2026, 6, 10, 13, 0, 0))
    create(:order_item, order: o)
    o.recalculate_totals!
    o.update_columns(order_number: number, **attrs)
    create(:payment, order: o, payment_method: method, amount_cents: o.total_cents)
    o.reload
  end

  let!(:first) { order(number: "7", customer: mona, method: "card", offline_number: "OFF-A3") }
  let!(:second) { order(number: "8", customer: zain, method: "cash", notes: "no onions", table_number: "45") }
  let!(:third) { order(number: "17") }

  def listed?(o) = response.body.include?(pos_order_path(o, from: "shift"))

  def search(query)
    get pos_shift_path(tab: "orders", filter: "all", q: query)
  end

  def listed_in_order(*orders)
    orders.map { |o| response.body.index(pos_order_path(o, from: "shift")) }
  end

  it "finds an order by its exact number, with or without #" do
    search("7")
    expect([listed?(first), listed?(third)]).to eq([true, false])

    search("#17")
    expect([listed?(third), listed?(first)]).to eq([true, false])
  end

  it "finds by customer name, phone (Arabic-Indic digits too), offline number, notes and table" do
    search("mona")
    expect([listed?(first), listed?(second)]).to eq([true, false])

    search("٣٣٣٣")
    expect([listed?(second), listed?(first)]).to eq([true, false])

    search("off-a3")
    expect([listed?(first), listed?(second)]).to eq([true, false])

    search("onion")
    expect([listed?(second), listed?(first)]).to eq([true, false])

    search("45")
    expect([listed?(second), listed?(first), listed?(third)]).to eq([true, false, false])
  end

  it "finds by an item on the order" do
    item_name = second.order_items.first.display_name
    first.order_items.each { |i| i.menu_item&.update_columns(name: "Something else") }
    third.order_items.each { |i| i.menu_item&.update_columns(name: "Something else") }

    search(item_name)
    expect(listed?(second)).to be(true)
  end

  it "shows the offline number in its own column" do
    get pos_shift_path(tab: "orders", filter: "all")
    expect(response.body).to include("OFF-A3")
  end

  it "sorts by customer name, with orders that have no customer last" do
    get pos_shift_path(tab: "orders", filter: "all", sort: "customer", dir: "asc")
    positions = listed_in_order(first, second, third)
    expect(positions).to eq(positions.sort)
  end

  it "sorts by payment method and by offline number" do
    get pos_shift_path(tab: "orders", filter: "all", sort: "payment", dir: "asc")
    positions = listed_in_order(first, second) # card before cash
    expect(positions).to eq(positions.sort)

    get pos_shift_path(tab: "orders", filter: "all", sort: "offline", dir: "desc")
    expect(listed_in_order(first, second).first).to be < listed_in_order(first, second).last
  end

  it "keeps the search when sorting" do
    get pos_shift_path(tab: "orders", filter: "all", q: "mona")
    expect(response.body).to include("q=mona")
  end
end
