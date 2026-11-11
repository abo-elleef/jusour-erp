# frozen_string_literal: true

require "rails_helper"

# Cashier picks Delivery first, then the customer. The customer's default address
# must show up in the delivery section straight away — not only after toggling the
# order type away and back.
RSpec.describe "Delivery address on attaching a customer", type: :request do
  include Devise::Test::IntegrationHelpers

  TURBO_HEADERS = { "Accept" => "text/vnd.turbo-stream.html, text/html" }.freeze

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }
  let(:customer) { create(:customer, company: company, name: "Nadia", phone: "01000000001") }

  before do
    Current.company = company
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    customer.addresses.create!(address: "12 Nile St, Zamalek", is_default: true)
    sign_in cashier
    open_drawer_for(cashier, location: branch)
  end

  def start_delivery_cart!
    post pos_order_items_path, params: { menu_item_id: menu_item.id }
    patch pos_update_fulfillment_path, params: { order_type: "delivery" }, headers: TURBO_HEADERS
    Current.company = company
    Order.find(session[:current_order_id])
  end

  def attach!(**params)
    patch "/pos/attach_customer", params: params, headers: TURBO_HEADERS
    Current.company = company
  end

  it "saves the default address and re-renders the delivery section with it" do
    order = start_delivery_cart!
    expect(order).to be_delivery

    attach!(customer_id: customer.id)

    expect(order.reload.delivery_address).to eq("12 Nile St, Zamalek")
    expect(response.body).to include('target="drawer-fulfillment-body"')
    expect(response.body).to include("12 Nile St, Zamalek")
  end

  it "re-renders the delivery section without the address when the customer is cleared" do
    order = start_delivery_cart!
    attach!(customer_id: customer.id)

    attach!(clear: "1")

    expect(order.reload.delivery_address).to be_nil
    expect(response.body).to include('target="drawer-fulfillment-body"')
    expect(response.body).not_to include("12 Nile St, Zamalek")
  end
end
