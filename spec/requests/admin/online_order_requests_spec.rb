# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin online orders", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, company: company, role: "owner") }
  let(:branch) { online_branch(company) }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
    sign_in owner
  end

  it "lists requests with status filters and links accepted ones to their order" do
    accepted = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request
    order = OnlineOrders::AcceptService.call(request: accepted, user: owner).order
    rejected = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item, phone: "01111111111")).request
    OnlineOrders::RejectService.call(request: rejected, user: owner, reason: "suspicious")

    get admin_online_order_requests_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_order_path(order))

    get admin_online_order_requests_path(q: { status_eq: "rejected" })
    expect(response.body).to include("01111111111")
    expect(response.body).not_to include("01001234567")
  end

  it "filters admin orders by source" do
    request_record = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request
    online = OnlineOrders::AcceptService.call(request: request_record, user: owner).order

    get admin_orders_path(q: { source_eq: "online" })

    expect(response.body).to include(admin_order_path(online))
  end

  it "is hidden from cashiers" do
    sign_in create(:user, company: company, role: "cashier")

    get admin_online_order_requests_path

    expect(response).not_to have_http_status(:ok)
  end
end
