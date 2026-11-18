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

  it "shows who the caller is on the request and a trust label in the inbox" do
    create(:customer, company: company, name: "Karim", phone: "010 0123 4567")
    request_record

    get pos_online_order_request_path(request_record)
    card = Nokogiri::HTML(response.body).at("[data-testid=online-order-customer-check]")
    expect(card.text).to include("Karim")
    expect(card.at("[data-testid=online-order-trust]")["data-level"]).to eq("caution") # typed "Mona"
    expect(card.at("[data-testid=online-order-check-reasons]").text).to include("(Karim)")

    get pos_online_order_requests_path
    expect(Nokogiri::HTML(response.body).at("[data-testid=online-order-trust]")["data-level"]).to eq("caution")
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

  it "opens a decided request with who rejected it, the note, and the check as it was then" do
    patch reject_pos_online_order_request_path(request_record),
          params: { reason: "no_answer", block: "1", note: "Called twice, phone off" }
    expect(request_record.reload.reject_note).to eq("Called twice, phone off")
    expect(request_record.blocked_phone).to be(true)
    expect(request_record.checks.keys).to contain_exactly("created", "decided")

    get pos_online_order_requests_path
    expect(response.body).to include(pos_online_order_request_path(request_record))

    get pos_online_order_request_path(request_record)
    doc = Nokogiri::HTML(response.body)
    decision = doc.at("[data-testid=online-order-decision]").text
    expect(decision).to include(I18n.t("pos.online_orders.story.rejected_by"), cashier.name, "Called twice, phone off",
                                    I18n.t("pos.online_orders.story.blocked_phone"))
    # Saved before the block, so it still says "new" rather than today's "blocked".
    expect(doc.at("[data-testid=online-order-trust]")["data-level"]).to eq("new")
    expect(response.body).not_to include(accept_pos_online_order_request_path(request_record))
  end

  it "shows a long-time walk-in regular as trusted, with their spend and last order" do
    regular = create(:customer, company: company, name: "Mona Saleh", phone: "01001234567")
    5.times do
      create(:order, user: cashier, customer: regular, location: branch, status: "completed",
                     total_cents: 20_000, placed_at: 3.days.ago)
    end

    get pos_online_order_request_path(request_record)
    card = Nokogiri::HTML(response.body).at("[data-testid=online-order-customer-check]")
    expect(card.at("[data-testid=online-order-trust]")["data-level"]).to eq("trusted")
    expect(card.text).to include("Mona Saleh", "1,000.00", branch.name)

    patch accept_pos_online_order_request_path(request_record)
    expect(request_record.reload).to be_accepted
    expect(request_record.check_snapshot(:decided).level).to eq("trusted")
    expect(request_record.check_snapshot(:decided).completed_count).to eq(5)
  end

  it "shows a customer whose earlier online orders were accepted as returning, with the accepted count" do
    Current.company = company # the request in `before` cleared it
    2.times do
      earlier = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item)).request
      order = OnlineOrders::AcceptService.call(request: earlier, user: cashier).order
      Orders::CompleteService.call(order.reload)
    end

    get pos_online_order_request_path(request_record)
    card = Nokogiri::HTML(response.body).at("[data-testid=online-order-customer-check]")
    expect(card.at("[data-testid=online-order-trust]")["data-level"]).to eq("returning")
    expect(card.text).to include("#{I18n.t("pos.online_orders.statuses.accepted")}: 2")
    expect(request_record.check_snapshot(:created).requests_by_status).to eq("accepted" => 2)
  end
end
