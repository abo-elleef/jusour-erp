# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::SessionSalesSummary do
  let(:company) { Current.company }
  let(:branch) { create(:location, company: company) }
  let(:user) { create(:user, company: company) }
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Drawer",
      treasury_type: "cash_drawer",
      balance_cents: 0,
      active: true
    )
  end
  let(:session) do
    CashDrawerSession.create!(
      user: user,
      treasury: treasury,
      location: branch,
      session_date: BusinessDay.today,
      opening_float_cents: 5000,
      status: "open"
    )
  end

  def pay!(method:, amount_cents:, session: nil)
    order = create(:order, user: user, company: company, status: "completed",
      subtotal_cents: amount_cents, total_cents: amount_cents)
    create(:payment, order: order, payment_method: method, amount_cents: amount_cents,
      cash_drawer_session: session)
  end

  it "sums cash and digital wallet sales for a session" do
    pay!(method: "cash", amount_cents: 2000, session: session)
    pay!(method: "instapay", amount_cents: 1500, session: session)
    pay!(method: "vodafone_cash", amount_cents: 800, session: session)

    summary = described_class.for_session(session)
    expect(summary.opening_float_cents).to eq(5000)
    expect(summary.cash_net_cents).to eq(2000)
    expect(summary.instapay_cents).to eq(1500)
    expect(summary.vodafone_cash_cents).to eq(800)
    expect(summary.total_sales_cents).to eq(4300)
    expect(summary.expected_cash_cents).to eq(7000)
  end

  describe "delivery fees" do
    def delivery!(method:, food_cents:, fee_cents:, status: "completed")
      order = create(:order, user: user, company: company, status: status, order_type: "delivery",
        delivery_address: "12 Nile St", subtotal_cents: food_cents, delivery_fee_cents: fee_cents,
        total_cents: food_cents + fee_cents, delivery_fee_drawer_session: session)
      create(:payment, order: order, payment_method: method, amount_cents: food_cents + fee_cents,
        cash_drawer_session: session)
    end

    it "leaves the fee out of expected cash when the driver kept it from a cash order" do
      delivery!(method: "cash", food_cents: 10_000, fee_cents: 2_000)

      summary = described_class.for_session(session)
      expect(summary.cash_net_cents).to eq(12_000)
      expect(summary.driver_payout_cents).to eq(2_000)
      expect(summary.expected_cash_cents).to eq(5_000 + 10_000)
    end

    it "takes the fee out of the drawer for an order paid by InstaPay" do
      delivery!(method: "instapay", food_cents: 10_000, fee_cents: 2_000)

      summary = described_class.for_session(session)
      expect(summary.instapay_cents).to eq(12_000)
      expect(summary.expected_cash_cents).to eq(5_000 - 2_000)
    end

    it "pays nothing out for a voided order" do
      delivery!(method: "cash", food_cents: 10_000, fee_cents: 2_000, status: "cancelled")

      expect(described_class.for_session(session).driver_payout_cents).to eq(0)
    end
  end

  it "falls back to the time window for payments without a session link" do
    session
    pay!(method: "cash", amount_cents: 1000, session: nil)
    pay!(method: "instapay", amount_cents: 500, session: nil)

    summary = described_class.for_session(session)
    expect(summary.cash_net_cents).to eq(1000)
    expect(summary.instapay_cents).to eq(500)
  end
end
