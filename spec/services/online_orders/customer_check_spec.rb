# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnlineOrders::CustomerCheck do
  let(:company) { create(:company) }
  let(:branch) { online_branch(company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:item) { create(:menu_item, company: company, name: "Koshary", base_price_cents: 5_000) }
  let(:area) { branch.delivery_areas.create!(company: company, name: "Dokki", fee_cents: 1_500) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
  end

  # Earlier waiting requests are moved aside so the per-phone pending cap doesn't bite.
  def submit(ip: "1.2.3.4", **overrides)
    OnlineOrderRequest.pending.update_all(status: "expired")
    result = OnlineOrders::SubmitService.call(location: branch, params: online_params(item: item, **overrides), ip: ip)
    raise "submit failed: #{result.error}" unless result.ok?

    result.request
  end

  def past_order(customer, status: "completed", total: 10_000, placed: true, address: nil)
    order = create(:order, user: cashier, customer: customer, location: branch, status: status, total_cents: total,
                           placed_at: 2.days.ago, order_type: (address ? "delivery" : "pickup"), delivery_address: address)
    order.update_column(:placed_at, nil) unless placed # a cart dropped before it reached the kitchen
    order
  end

  def check(request) = described_class.new(request)

  it "calls an unknown phone new, with no match" do
    result = check(submit)

    expect(result.customer).to be_nil
    expect(result.level).to eq("new")
    expect(result.reasons).to be_empty
  end

  it "finds a customer whose phone was typed with spaces or without the leading 0" do
    spaced = create(:customer, company: company, name: "Mona", phone: "010 0123 4567")
    expect(check(submit).customer).to eq(spaced)

    spaced.update!(phone: nil, phone_secondary: "1001234567")
    expect(OnlineOrders::FindOrCreateCustomer.lookup("01001234567")).to eq(spaced)
  end

  it "grades by completed orders: returning, then trusted" do
    mona = create(:customer, company: company, name: "Mona Ali", phone: "01001234567")
    past_order(mona)
    expect(check(submit).level).to eq("returning")

    2.times { past_order(mona) }
    result = check(submit)
    expect(result.level).to eq("trusted")
    expect(result.completed_count).to eq(3)
    expect(result.total_spent_cents).to eq(30_000)
    expect(result.last_order.location).to eq(branch)
  end

  it "shows a blocked customer as blocked" do
    mona = create(:customer, company: company, name: "Mona", phone: "01001234567")
    request = submit
    mona.block!(by: cashier, reason: "fake")

    expect(check(request.reload).level).to eq("blocked")
  end

  it "warns when the typed name differs from the name on file, but not for spelling or extra words" do
    create(:customer, company: company, name: "Karim Hassan", phone: "01001234567")
    3.times { past_order(Customer.last) }

    expect(check(submit(customer_name: "Mona")).reasons).to eq([:name_mismatch])
    expect(check(submit(customer_name: "kareem hassan")).name_mismatch?).to be(false)
    expect(check(submit(customer_name: "Karim")).level).to eq("trusted")
  end

  it "treats Arabic letter variants as the same name" do
    create(:customer, company: company, name: "أحمد محمود", phone: "01001234567")

    expect(check(submit(customer_name: "احمد")).name_mismatch?).to be(false)
  end

  it "warns about earlier rejections from the same phone" do
    first = submit
    OnlineOrders::RejectService.call(request: first, user: cashier, reason: "no_answer", block: false)

    result = check(submit)
    expect(result.level).to eq("caution")
    expect(result.reasons).to include(:earlier_rejections)
    expect(result.rejection_reasons).to eq("no_answer" => 1)
  end

  it "warns when the same device ordered with other phones this week" do
    submit(phone: "01111111111", ip: "9.9.9.9")
    submit(phone: "01222222222", ip: "9.9.9.9")

    result = check(submit(ip: "9.9.9.9"))
    expect(result.shared_device_phones).to eq(2)
    expect(result.reasons).to include(:shared_device)
  end

  it "warns after two orders voided once placed, ignoring abandoned carts" do
    mona = create(:customer, company: company, name: "Mona", phone: "01001234567")
    past_order(mona, status: "cancelled")
    past_order(mona, status: "cancelled", placed: false)
    expect(check(submit).reasons).to be_empty

    past_order(mona, status: "cancelled")
    expect(check(submit).reasons).to eq([:voided_orders])
  end

  it "knows whether a delivery address was used before" do
    mona = create(:customer, company: company, name: "Mona", phone: "01001234567")
    past_order(mona, address: "12  Nile St, flat 4")

    expect(check(submit(area: area)).address_status).to eq(:known)
    expect(check(submit(area: area, address: "Somewhere else")).address_status).to eq(:new)
    expect(check(submit).address_status).to be_nil
  end
end
