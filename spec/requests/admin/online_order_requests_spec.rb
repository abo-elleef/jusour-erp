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

  it "shows the whole story of a request: what was sent, checks then, and who decided" do
    accepted = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request
    OnlineOrders::AcceptService.call(request: accepted, user: owner)
    rejected = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request
    OnlineOrders::RejectService.call(request: rejected, user: owner, reason: "suspicious", note: "Same caller as yesterday")

    get admin_online_order_requests_path
    expect(response.body).to include(admin_online_order_request_path(rejected))

    get admin_online_order_request_path(rejected)
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML(response.body)
    expect(doc.at("[data-testid=online-order-decision]").text).to include(I18n.t("pos.online_orders.story.rejected_by"), owner.name, "Same caller as yesterday")
    expect(doc.css("[data-testid=online-order-customer-check]").size).to eq(1) # as the cashier saw it when deciding
    expect(response.body).to include("Koshary")
    expect(response.body).to include(admin_online_order_request_path(accepted)) # same phone list

    get admin_online_order_request_path(accepted)
    expect(response.body).to include(admin_order_path(accepted.reload.order))
  end

  it "links the customer's last order to its admin order page" do
    regular = create(:customer, company: company, name: "Mona Saleh", phone: "01001234567")
    last = create(:order, user: owner, customer: regular, location: branch, status: "completed",
                          total_cents: 15_000, placed_at: 2.days.ago)
    request = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request

    get admin_online_order_request_path(request)
    links = Nokogiri::HTML(response.body).css("[data-testid=online-order-check-last-order]")
    expect(links).not_to be_empty
    expect(links.map { |a| a["href"] }.uniq).to eq([admin_order_path(last)])
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
