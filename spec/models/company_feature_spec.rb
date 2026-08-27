# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, "business profile & feature flags", type: :model do
  it "defaults to the restaurant profile" do
    expect(create(:company).business_type).to eq("restaurant")
  end

  it "validates business_type" do
    c = build(:company, business_type: "bogus")
    expect(c).not_to be_valid
    expect(c.errors[:business_type]).to be_present
  end

  describe "#feature_enabled? by profile default" do
    it "restaurant: manufacturing/attendance ON, credit-sales/tiers OFF" do
      c = build(:company, business_type: "restaurant")
      expect(c.feature_enabled?(:manufacturing)).to be(true)
      expect(c.feature_enabled?(:attendance)).to be(true)
      expect(c.feature_enabled?(:ar_credit_sales)).to be(false)
      expect(c.feature_enabled?(:price_tiers)).to be(false)
    end

    it "distribution: manufacturing/attendance/kds/menu OFF, credit-sales/tiers ON" do
      c = build(:company, business_type: "distribution")
      expect(c.feature_enabled?(:manufacturing)).to be(false)
      expect(c.feature_enabled?(:attendance)).to be(false)
      expect(c.feature_enabled?(:kds)).to be(false)
      expect(c.feature_enabled?(:menu)).to be(false)
      expect(c.feature_enabled?(:ar_credit_sales)).to be(true)
      expect(c.feature_enabled?(:price_tiers)).to be(true)
    end
  end

  describe "per-company overrides win over the profile default" do
    it "can force a normally-off feature on" do
      c = build(:company, business_type: "restaurant", feature_overrides: { "ar_credit_sales" => true })
      expect(c.feature_enabled?(:ar_credit_sales)).to be(true)
    end

    it "can force a normally-on feature off" do
      c = build(:company, business_type: "distribution", feature_overrides: { "manufacturing" => true })
      expect(c.feature_enabled?(:manufacturing)).to be(true)

      c2 = build(:company, business_type: "restaurant", feature_overrides: { "manufacturing" => false })
      expect(c2.feature_enabled?(:manufacturing)).to be(false)
    end
  end

  it "accepts a string or symbol feature key" do
    c = build(:company, business_type: "distribution")
    expect(c.feature_enabled?("manufacturing")).to be(false)
    expect(c.feature_enabled?(:manufacturing)).to be(false)
  end
end
