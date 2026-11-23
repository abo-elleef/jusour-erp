# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnlineOrders::SubmitService do
  let(:company) { create(:company) }
  let(:branch) { online_branch(company) }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let(:area) { branch.delivery_areas.create!(company: company, name: "Dokki", fee_cents: 1_500) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  def submit(ip: "1.2.3.4", **overrides)
    described_class.call(location: branch, params: online_params(item: item, **overrides), ip: ip)
  end

  it "saves a pending request priced on the server, with the area fee" do
    result = submit(area: area, items: [{ "menu_item_id" => item.id, "quantity" => 2, "unit_price_cents" => 1 }])

    expect(result).to be_ok
    request = result.request
    expect(request).to be_pending
    expect(request.phone).to eq("01001234567")
    expect(request.total_cents).to eq(10_000 + 1_500)
    expect(request.expires_at).to be_within(5.seconds).of(10.minutes.from_now)
    expect(OnlineOrders::ExpireJob).to have_been_enqueued.with(request.id)
  end

  it "creates no customer for a new phone" do
    expect { submit }.not_to change(Customer, :count)
  end

  it "links an existing customer stored with another phone format" do
    customer = create(:customer, company: company, phone: "+201001234567")

    expect(submit.request.customer).to eq(customer)
  end

  {
    "branch is not taking orders" => [:closed, -> { branch.update!(online_ordering_enabled: false) }, {}],
    "honeypot is filled" => [:spam, nil, { website: "http://spam" }],
    "stamp is forged" => [:spam, nil, { started_at: "123" }],
    "phone is not an Egyptian mobile" => [:invalid_phone, nil, { phone: "12345" }],
    "name is missing" => [:missing_name, nil, { customer_name: " " }],
    "delivery without area" => [:missing_area, nil, { fulfillment: "delivery" }],
    "cart is empty" => [:empty_cart, nil, { items: [] }]
  }.each do |label, (code, setup, overrides)|
    it "refuses when #{label}" do
      instance_exec(&setup) if setup

      expect(submit(**overrides).error).to eq(code)
    end
  end

  it "refuses a form sent the instant the page opened" do
    expect(submit(started_at: described_class.page_stamp).error).to eq(:spam)
  end

  it "refuses outside online hours" do
    branch.update!(online_open_time: "10:00", online_close_time: "11:00")

    noon = Time.utc(2026, 11, 14, 12, 0)
    params = online_params(item: item, started_at: described_class.page_stamp(noon - 2.hours))

    expect(described_class.call(location: branch, params: params, now: noon).error).to eq(:closed)
    expect(described_class.call(location: branch, params: params, now: noon - 90.minutes)).to be_ok
  end

  it "refuses a blocked customer" do
    create(:customer, company: company, phone: "01001234567").block!(by: nil, reason: "spam")

    expect(submit.error).to eq(:blocked)
  end

  it "caps waiting requests per phone" do
    2.times { expect(submit).to be_ok }

    expect(submit.error).to eq(:too_many_pending)
  end

  it "caps requests per connection per hour" do
    described_class::MAX_PER_IP_PER_HOUR.times { |i| submit(phone: "0100000#{i.to_s.rjust(4, '0')}") }

    expect(submit(phone: "01099999999").error).to eq(:too_many_requests)
  end

  it "refuses cash above the pay-first amount when the branch has no pay-first method" do
    branch.update!(online_max_order_cents: 9_000)

    expect(submit.error).to eq(:too_large)
  end

  it "refuses an item that is off at the branch" do
    LocationMenuItem.find_by!(location: branch, menu_item: item).update!(available: false)

    expect(submit.error).to eq(:bad_items)
  end
end
