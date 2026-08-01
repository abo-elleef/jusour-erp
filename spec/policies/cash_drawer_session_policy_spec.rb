# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashDrawerSessionPolicy do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:other_cashier) { create(:user, company: company, role: "cashier", email: "other@example.com") }
  let(:manager) { create(:user, :manager, company: company) }
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Register",
      treasury_type: "cash_drawer",
      balance_cents: 50_000,
      opening_balance_cents: 50_000
    )
  end
  let(:session) do
    CashDrawerSession.create!(
      user: cashier,
      treasury: treasury,
      location: branch,
      session_date: Date.current,
      opening_float_cents: 10_000,
      status: "open"
    )
  end

  before { Current.company = company }

  describe "#count?" do
    it "allows the owning cashier" do
      expect(described_class.new(cashier, session).count?).to be(true)
    end

    it "denies another cashier" do
      expect(described_class.new(other_cashier, session).count?).to be(false)
    end

    it "denies when session is reconciled" do
      session.update!(status: "reconciled", counted_cash_cents: 10_000, variance_cents: 0, expected_cash_cents: 10_000)
      expect(described_class.new(cashier, session).count?).to be(false)
    end
  end

  describe "#open_drawer?" do
    it "allows POS users" do
      expect(described_class.new(cashier, CashDrawerSession).open_drawer?).to be(true)
    end
  end
end
