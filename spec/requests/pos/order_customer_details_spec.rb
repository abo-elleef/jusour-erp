# frozen_string_literal: true

require "rails_helper"

# Opening an order from My Shift shows the customer's full details: name, phones,
# email, this order's delivery address, other saved addresses and the standing note.
RSpec.describe "POS order page customer details", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:customer) do
    create(:customer, company: company, name: "Mona Adel", phone: "01011112222",
                      phone_secondary: "01233334444", email: "mona@example.com",
                      standing_note: "Ring twice")
  end

  before do
    Current.company = company
    customer.addresses.create!(label: "Home", address: "12 Nile St", is_default: true)
    customer.addresses.create!(label: "Work", address: "5 Tahrir Sq")
    sign_in cashier
  end

  def make_order(**attrs)
    Current.company = company
    o = create(:order, user: cashier, company: company, location: branch, status: "completed", **attrs)
    create(:order_item, order: o)
    o.recalculate_totals!
    o
  end

  it "shows every customer detail on a delivery order opened from the shift" do
    o = make_order(order_type: "delivery", customer: customer, delivery_address: "12 Nile St")
    get pos_order_path(o, from: "shift")

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("order-customer-details", "Mona Adel", "tel:01011112222", "tel:01233334444",
                            "mona@example.com", "Ring twice", "5 Tahrir Sq")
    expect(body).to include('data-testid="order-customer-delivery-address">12 Nile St')
    # The delivery address is not repeated under the saved addresses.
    expect(body.scan("12 Nile St").size).to eq(2) # card + edit-details textarea
  end

  it "shows no customer card when the order has no customer" do
    o = make_order(order_type: "pickup")
    get pos_order_path(o, from: "shift")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("order-customer-details")
  end
end
