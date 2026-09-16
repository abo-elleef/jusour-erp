# frozen_string_literal: true

require "rails_helper"

# The end-of-day read a manager does over a branch's shifts.
RSpec.describe Accounting::DrawerDayReport do
  include ActiveSupport::Testing::TimeHelpers

  # Pinned to midday: before the business-day start hour the calendar date and the
  # business date are different days, and these sessions are dated by hand.
  around { |example| travel_to(Time.zone.local(2026, 6, 10, 12, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, name: "Branch A") }
  let(:other_branch) { create(:location, company: company, name: "Branch B") }
  let(:date) { Date.current }

  let(:till_one) { drawer_treasury("Till 1") }
  let(:till_two) { drawer_treasury("Till 2") }
  let!(:safe) do
    Treasury.create!(company: company, name: "Safe", treasury_type: "safe",
      balance_cents: 0, opening_balance_cents: 0)
  end

  before { Current.company = company }

  def drawer_treasury(name)
    Treasury.create!(company: company, name: name, treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0)
  end

  def shift(treasury:, location: branch, float: 10_000, counted: nil, cash: 0,
            instapay: 0, vodafone: 0, deposit: nil)
    session = CashDrawerSession.create!(
      company: company, user: create(:user, company: company), treasury: treasury,
      location: location, session_date: date, opening_float_cents: float,
      status: counted ? "reconciled" : "open",
      counted_cash_cents: counted, deposit_treasury: deposit
    )
    { "cash" => cash, "instapay" => instapay, "vodafone_cash" => vodafone }.each do |method, cents|
      next if cents.zero?

      order = create(:order, user: session.user, company: company, location: location,
                             status: "completed", total_cents: cents)
      create(:payment, order: order, amount_cents: cents, status: "completed",
                       payment_method: method, cash_drawer_session: session)
    end
    ::Accounting::CashReconciliationService.new(session).compute_expected!
    session
  end

  describe "a branch's day" do
    it "returns a row per shift, oldest first" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, cash: 3_000)

      rows, totals = described_class.call(date: date, location: branch)

      expect(rows.size).to eq(2)
      expect(totals.shifts).to eq(2)
    end

    it "totals the takings by tender" do
      shift(treasury: till_one, cash: 5_000, instapay: 2_000)
      shift(treasury: till_two, cash: 3_000, vodafone: 1_500)

      _rows, totals = described_class.call(date: date, location: branch)

      expect(totals.cash_cents).to eq(8_000)
      expect(totals.instapay_cents).to eq(2_000)
      expect(totals.vodafone_cash_cents).to eq(1_500)
      expect(totals.total_sales_cents).to eq(11_500)
    end

    it "quotes the same cash figure the cashier's own count screen would" do
      session = shift(treasury: till_one, cash: 5_000)
      rows, _totals = described_class.call(date: date, location: branch)

      expect(rows.first.cash_cents)
        .to eq(::Accounting::SessionSalesSummary.for_session(session).cash_net_cents)
    end

    it "leaves another branch's shifts out" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_two, location: other_branch, cash: 9_000)

      _rows, totals = described_class.call(date: date, location: branch)

      expect(totals.shifts).to eq(1)
      expect(totals.cash_cents).to eq(5_000)
    end

    it "leaves another day's shifts out" do
      shift(treasury: till_one, cash: 5_000)
      CashDrawerSession.update_all(session_date: date - 1)

      _rows, totals = described_class.call(date: date, location: branch)

      expect(totals.shifts).to eq(0)
    end
  end

  describe "filtering by drawer" do
    it "narrows to that till across the cashiers who shared it" do
      shift(treasury: till_one, cash: 5_000)
      shift(treasury: till_one, cash: 2_000)
      shift(treasury: till_two, cash: 9_000)

      _rows, totals = described_class.call(date: date, location: branch, treasury: till_one)

      expect(totals.shifts).to eq(2)
      expect(totals.cash_cents).to eq(7_000)
    end
  end

  describe "what has been closed" do
    it "counts a drawer nobody has counted as contributing nothing counted" do
      shift(treasury: till_one, cash: 5_000)

      _rows, totals = described_class.call(date: date, location: branch)

      expect(totals.counted_cents).to eq(0)
      expect(totals.fully_closed?).to be false
      expect(totals.open_shifts).to eq(1)
    end

    it "reports the day closed once every drawer is" do
      shift(treasury: till_one, cash: 5_000, counted: 15_000, deposit: safe)

      _rows, totals = described_class.call(date: date, location: branch)

      expect(totals.counted_cents).to eq(15_000)
      expect(totals.deposited_cents).to eq(15_000)
      expect(totals.fully_closed?).to be true
    end

    it "counts nothing banked for a drawer with no destination" do
      shift(treasury: till_one, cash: 5_000, counted: 15_000)

      _rows, totals = described_class.call(date: date, location: branch)

      expect(totals.deposited_cents).to eq(0)
    end
  end
end
