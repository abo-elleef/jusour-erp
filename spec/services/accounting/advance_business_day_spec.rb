# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::AdvanceBusinessDay do
  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let(:branch_a) { create(:location, company: company, name: "Branch A", business_day_mode: "manual") }
  let(:branch_b) { create(:location, company: company, name: "Branch B", business_day_mode: "manual") }
  let(:cashier) { create(:user, company: company, role: "cashier", name: "Ahmed") }
  let(:treasury) do
    Treasury.create!(
      company: company,
      name: "Drawer",
      treasury_type: "cash_drawer",
      balance_cents: 0,
      active: true
    )
  end

  before do
    LocationOperatingDay.ensure_open!(branch_a, date: Date.new(2026, 4, 1), user: owner)
    LocationOperatingDay.ensure_open!(branch_b, date: Date.new(2026, 4, 1), user: owner)
  end

  def open_drawer!(location)
    CashDrawerSession.create!(
      user: cashier,
      treasury: treasury,
      location: location,
      session_date: BusinessDay.today(location: location),
      opening_float_cents: 0,
      status: "open"
    )
  end

  describe ".call" do
    it "rejects when the branch is automatic" do
      branch_a.update!(business_day_mode: "automatic")
      result = described_class.call(location: branch_a, user: owner)
      expect(result).not_to be_success
      expect(result.error).to eq(I18n.t("accounting.business_days.errors.not_manual"))
    end

    it "blocks when the branch has an open drawer" do
      open_drawer!(branch_a)
      result = described_class.call(location: branch_a, user: owner)
      expect(result).not_to be_success
      expect(result.error).to include("Ahmed")
      expect(BusinessDay.today(location: branch_a)).to eq(Date.new(2026, 4, 1))
    end

    it "advances the operating day when drawers are clear" do
      result = described_class.call(location: branch_a, user: owner)
      expect(result).to be_success
      expect(result.from_date).to eq(Date.new(2026, 4, 1))
      expect(result.to_date).to eq(Date.new(2026, 4, 2))
      expect(BusinessDay.today(location: branch_a)).to eq(Date.new(2026, 4, 2))
      expect(LocationOperatingDay.current_for(branch_a).opened_by).to eq(owner)
    end
  end

  describe ".call_all" do
    it "advances clear manual branches, skips automatic, and reports blocked ones" do
      automatic = create(:location, company: company, name: "Auto Branch", business_day_mode: "automatic")
      open_drawer!(branch_a)

      batch = described_class.call_all(user: owner)

      expect(batch.advanced.map { |r| r.location.id }).to eq([branch_b.id])
      expect(batch.failed.map { |r| r.location.id }).to eq([branch_a.id])
      expect(batch.skipped.map { |r| r.location.id }).to include(automatic.id)
      expect(BusinessDay.today(location: branch_a)).to eq(Date.new(2026, 4, 1))
      expect(BusinessDay.today(location: branch_b)).to eq(Date.new(2026, 4, 2))
    end
  end
end
