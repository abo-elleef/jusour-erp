# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS online orders inbox", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { online_branch(company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let(:request_record) { OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    get pos_path
  end

  it "shows the Online tab with the waiting count and lists the request" do
    request_record
    get pos_online_order_requests_path

    doc = Nokogiri::HTML(response.body)
    expect(doc.at("#online-orders-badge").text.strip).to eq("1")
    expect(response.body).to include("Mona")
  end

  it "accepts into the cashier's own order" do
    patch accept_pos_online_order_request_path(request_record)

    order = request_record.reload.order
    expect(order.user).to eq(cashier)
    expect(flash[:notice]).to include(order.order_number.to_s)
  end

  it "puts the accepted order on the cashier's register so its receipt prints there" do
    register = Workstation.create!(company: company, location: branch, name: "Front", active: true)
    get pos_path # the branch's only register is picked for this session

    patch accept_pos_online_order_request_path(request_record)

    expect(request_record.reload.order.workstation).to eq(register)
  end

  it "won't accept without an open drawer" do
    CashDrawerSession.where(user: cashier).update_all(status: "closed")

    patch accept_pos_online_order_request_path(request_record)

    expect(request_record.reload).to be_pending
  end

  it "rejects and blocks" do
    patch reject_pos_online_order_request_path(request_record), params: { reason: "suspicious", block: "1" }

    expect(request_record.reload).to be_rejected
    expect(Customer.find_by(phone: "01001234567")).to be_blocked
  end

  it "pauses and resumes the branch" do
    patch toggle_pos_online_order_requests_path
    expect(branch.reload.online_ordering_enabled).to be(false)

    patch toggle_pos_online_order_requests_path
    expect(branch.reload.online_ordering_enabled).to be(true)
  end

  it "cannot see another branch's requests" do
    other = online_branch(company)
    create(:location_menu_item, location: other, menu_item: item, available: true)
    foreign = OnlineOrders::SubmitService.call(location: other, params: online_params(item: item, phone: "01111111111")).request

    get pos_online_order_request_path(foreign)

    expect(response).to have_http_status(:not_found)
  end
end
