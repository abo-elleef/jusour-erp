# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

# Branches that ask for the customer on pickup (Location#pickup_customer_prompt):
# Place order and Charge open a phone popup first; the cashier types the phone or
# skips with a reason. Without either, the order is not placed and no money is
# taken (Orders::SubmitService.validate_fulfillment!).
RSpec.describe "Pickup orders ask for the customer", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, pickup_customer_prompt: true) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }

  before do
    Current.company = company
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    sign_in cashier
    open_drawer_for(cashier, location: branch)
  end

  def start_cart!
    post pos_order_items_path, params: { menu_item_id: menu_item.id }
    Current.company = company
    Order.find(session[:current_order_id])
  end

  def pickup_customer(**params)
    patch pos_pickup_customer_path, params: params
    Current.company = company
  end

  it "shows the phone popup instead of placing straight away" do
    start_cart!
    get pos_path
    expect(response.body).to include('id="pickup-customer-dialog"')
    expect(response.body).to include('data-testid="place-order-pickup"')
  end

  it "refuses to place a pickup order with neither a customer nor a reason" do
    order = start_cart!
    patch pos_submit_path
    Current.company = company

    expect(order.reload.status).to eq("draft")
    expect(flash[:alert]).to eq(I18n.t("order.submit.errors.pickup_customer_required"))
  end

  it "takes no money from a pickup order with neither a customer nor a reason" do
    order = start_cart!
    expect do
      post pos_payments_path, params: { order_id: order.id, payment_method: "cash",
                                        amount_pounds: (order.reload.total_cents / 100.0).to_s }
    end.to not_change(Payment, :count)
    expect(order.reload.status).to eq("draft")
  end

  it "creates a customer from the phone alone and places the order" do
    order = start_cart!
    expect { pickup_customer(phone: "0100 123-4567", next: "place") }.to change(Customer, :count).by(1)

    order.reload
    expect(order.customer.phone).to eq("01001234567")
    expect(order.customer.name).to be_nil
    expect(order.status).to eq("submitted")
    expect(order.customer_skip_reason).to be_nil
  end

  it "reuses an existing customer by phone and reopens the register on the payment modal" do
    existing = create(:customer, company: company, name: "Mona", phone: "01001234567")
    order = start_cart!

    expect { pickup_customer(phone: "01001234567", next: "charge") }.not_to change(Customer, :count)

    expect(order.reload.customer).to eq(existing)
    expect(order.status).to eq("draft")
    expect(response).to redirect_to(pos_path(open_payment: 1))
  end

  it "keeps a typed name on a new customer" do
    order = start_cart!
    pickup_customer(phone: "01009998887", name: "Karim", next: "charge")
    expect(order.reload.customer.name).to eq("Karim")
  end

  it "gives a name to an existing customer who had none" do
    nameless = create(:customer, company: company, name: nil, phone: "01001112223")
    order = start_cart!
    pickup_customer(phone: "01001112223", name: "Samir", next: "charge")

    expect(order.reload.customer).to eq(nameless)
    expect(nameless.reload.name).to eq("Samir")
  end

  it "never renames a known customer" do
    named = create(:customer, company: company, name: "Mona", phone: "01001234567")
    order = start_cart!
    pickup_customer(phone: "01001234567", name: "Someone else", next: "charge")

    expect(order.reload.customer).to eq(named)
    expect(named.reload.name).to eq("Mona")
  end

  it "places the order after a skip and keeps the reason" do
    order = start_cart!
    expect { pickup_customer(skip_reason: "refused", next: "place") }.not_to change(Customer, :count)

    order.reload
    expect(order.customer_skip_reason).to eq("refused")
    expect(order.status).to eq("submitted")
  end

  it "refuses an unknown skip reason" do
    order = start_cart!
    pickup_customer(skip_reason: "bored", next: "place")
    expect(order.reload.customer_skip_reason).to be_nil
    expect(order.status).to eq("draft")
    expect(flash[:alert]).to eq(I18n.t("flash.pos.pickup_skip_reason_invalid"))
  end

  it "asks again when the phone is blank" do
    order = start_cart!
    pickup_customer(phone: " ", next: "place")
    expect(order.reload.status).to eq("draft")
    expect(flash[:alert]).to eq(I18n.t("flash.pos.pickup_phone_required"))
  end

  it "drops the skip reason once a customer is attached later" do
    order = start_cart!
    pickup_customer(skip_reason: "in_a_hurry", next: "charge")
    customer = create(:customer, company: company, phone: "01005556667")
    patch "/pos/attach_customer", params: { customer_id: customer.id },
                                  headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    Current.company = company

    expect(order.reload.customer_skip_reason).to be_nil
  end

  it "leaves other order types alone" do
    order = start_cart!
    patch pos_update_fulfillment_path, params: { order_type: "table", table_number: "4" }
    Current.company = company
    patch pos_submit_path
    expect(order.reload.status).to eq("submitted")
  end

  it "does not ask at a branch with the switch off" do
    branch.update!(pickup_customer_prompt: false)
    order = start_cart!
    get pos_path
    expect(response.body).not_to include('id="pickup-customer-dialog"')

    patch pos_submit_path
    expect(order.reload.status).to eq("submitted")
  end

  it "attaches a customer picked from the search list and carries on" do
    picked = create(:customer, company: company, name: "Mona", phone: "01001234567")
    order = start_cart!
    expect { pickup_customer(customer_id: picked.id, phone: "01001234567", next: "place") }.not_to change(Customer, :count)

    expect(order.reload.customer).to eq(picked)
    expect(order.status).to eq("submitted")
  end

  it "never makes a customer whose phone is a name" do
    order = start_cart!
    expect { pickup_customer(phone: "Mona", next: "place") }.not_to change(Customer, :count)
    expect(order.reload.status).to eq("draft")
    expect(flash[:alert]).to eq(I18n.t("flash.pos.pickup_phone_required"))
  end

  describe "search as you type" do
    let!(:mona) { create(:customer, company: company, name: "Mona", phone: "01001234567") }
    let!(:mostafa) { create(:customer, company: company, name: "Mostafa", phone: "01121234500") }
    let!(:karim) { create(:customer, company: company, name: "Karim", phone: "01559998887", phone_secondary: "01000001234") }

    def search(q)
      get customers_search_path(format: :json, q: q)
      response.parsed_body
    end

    it "matches any part of a phone from 4 digits, primary or secondary" do
      expect(search("1234")["results"].map { |c| c["name"] }).to contain_exactly("Mona", "Mostafa", "Karim")
      expect(search("1234")["exact"]).to be_nil
    end

    it "does not search on fewer than 4 digits" do
      expect(search("010")["results"]).to be_empty
    end

    it "matches by name from 2 letters" do
      expect(search("mo")["results"].map { |c| c["name"] }).to eq(%w[Mona Mostafa])
    end

    it "returns the exact match for a full number, first in the list" do
      body = search("0100 1234567")
      expect(body["exact"]).to include("id" => mona.id, "name" => "Mona", "phone" => "01001234567")
      expect(body["results"].first["id"]).to eq(mona.id)
    end

    it "labels a nameless customer by phone, with a blank name to prefill" do
      mona.update!(name: nil)
      expect(search("01001234567")["exact"]).to include("name" => "", "label" => "01001234567")
    end

    it "has no exact match for a new full number" do
      expect(search("01099999999")).to eq("exact" => nil, "results" => [])
    end
  end
end
