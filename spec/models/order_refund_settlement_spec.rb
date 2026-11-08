# frozen_string_literal: true

require "rails_helper"

# A refund gives the customer's money back; it does not re-open the bill. A payment
# refunded in full still settled the order, so nothing is owed on it.
RSpec.describe Order, "settlement after a refund" do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company) }

  before { Current.company = company }

  def completed_order(total: 10_000)
    order = create(:order, user: user, company: company, location: branch, status: "completed")
    create(:order_item, order: order, unit_price_cents: total)
    order.recalculate_totals!
    order
  end

  def pay(order, status:, refunded: 0)
    create(:payment, order: order, amount_cents: order.total_cents, status: status,
                     payment_method: "cash", refunded_amount_cents: refunded)
  end

  it "owes nothing on an order whose payment was refunded in full" do
    order = completed_order
    pay(order, status: "refunded", refunded: order.total_cents)

    expect(order.amount_due_cents).to eq(0)
    expect(order).to be_fully_paid
    expect(Order.unpaid).not_to include(order)
    expect(Order.not_fully_paid).not_to include(order)
  end

  it "still owes nothing after a partial refund" do
    order = completed_order
    pay(order, status: "partially_refunded", refunded: 2_000)

    expect(order.amount_due_cents).to eq(0)
    expect(Order.unpaid).not_to include(order)
  end

  it "keeps paid_cents as the money actually retained" do
    order = completed_order
    pay(order, status: "refunded", refunded: order.total_cents)

    expect(order.paid_cents).to eq(0)
    expect(order.settled_cents).to eq(order.total_cents)
  end

  it "still lists a genuinely unpaid order, and one whose payment failed" do
    unpaid = completed_order
    failed = completed_order
    pay(failed, status: "failed")

    expect(Order.unpaid).to include(unpaid, failed)
    expect(unpaid.amount_due_cents).to eq(unpaid.total_cents)
  end
end
