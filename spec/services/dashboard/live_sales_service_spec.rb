# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::LiveSalesService do
  include ActiveSupport::Testing::TimeHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 2501) }
  let(:north) { create(:location, company: company, name: "North") }
  let(:south) { create(:location, company: company, name: "South") }
  # 14:00 on a Monday; the business day starts at 06:00 by default.
  let(:now) { Time.zone.local(2026, 11, 16, 14, 0) }

  before { Current.company = company }
  around { |ex| travel_to(now) { ex.run } }

  def order(status:, at:, total:, location: north, delivery_fee: 0)
    create(:order, user: owner, company: company, status: status, location: location,
                   subtotal_cents: total, total_cents: total, delivery_fee_cents: delivery_fee, created_at: at)
  end

  it "counts placed orders that are not completed yet, and leaves drafts and cancelled ones out" do
    order(status: "submitted", at: now - 3.hours, total: 1000)
    order(status: "ready", at: now - 2.hours, total: 500, delivery_fee: 100)
    order(status: "completed", at: now - 1.hour, total: 2000)
    order(status: "draft", at: now - 1.hour, total: 9000)
    order(status: "cancelled", at: now - 1.hour, total: 9000)
    order(status: "completed", at: Time.zone.local(2026, 11, 16, 5, 0), total: 9000) # yesterday's business day

    result = described_class.call(now: now)

    expect(result.order_count).to eq(3)
    expect(result.sales_cents).to eq(3400) # delivery fee is the driver's
    expect(result.avg_cents).to eq(1133)
  end

  it "takes refunds off and reports what has been collected" do
    paid = order(status: "submitted", at: now - 1.hour, total: 1000)
    order(status: "submitted", at: now - 1.hour, total: 600)
    paid.payments.create!(payment_method: "cash", amount_cents: 1000, tip_cents: 0, status: "partially_refunded",
                          refunded_amount_cents: 200, processed_by_user: owner)

    result = described_class.call(now: now)

    expect(result.sales_cents).to eq(1400)
    expect(result.collected_cents).to eq(800)
  end

  it "compares with the same weekday last week up to the same time" do
    order(status: "submitted", at: now - 1.hour, total: 800)
    order(status: "completed", at: now - 7.days - 2.hours, total: 1000)  # last week, before this time
    order(status: "completed", at: now - 7.days + 3.hours, total: 5000)  # last week, later in the day

    result = described_class.call(now: now)

    expect(result.last_week_date).to eq(Date.new(2026, 11, 9))
    expect(result.last_week_same_time_cents).to eq(1000)
    expect(result.last_week_same_time_count).to eq(1)
    expect(result.last_week_full_day_cents).to eq(6000)
    expect(result.change_percent).to eq(-20)
  end

  it "splits by branch only when more than one branch sold, and limits to the given branches" do
    order(status: "submitted", at: now - 1.hour, total: 800, location: north)
    order(status: "submitted", at: now - 1.hour, total: 300, location: south)

    result = described_class.call(now: now)
    expect(result.by_branch.map { |b| [b[:name], b[:sales_cents]] }).to eq([["North", 800], ["South", 300]])

    scoped = described_class.call(location_ids: [south.id], now: now)
    expect(scoped.sales_cents).to eq(300)
    expect(scoped.by_branch).to eq([])
  end

  it "buckets sales by hour of the business day, with no figure for hours still to come" do
    order(status: "submitted", at: now - 30.minutes, total: 800)

    hours = described_class.call(now: now).by_hour
    expect(hours.first[:hour]).to eq("06:00")
    expect(hours.find { |h| h[:hour] == "13:00" }[:today_cents]).to eq(800)
    expect(hours.find { |h| h[:hour] == "15:00" }[:today_cents]).to be_nil
  end
end
