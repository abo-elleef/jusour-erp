# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer, "commercial profile (type, pricing, credit)", type: :model do
  let(:company) { create(:company) }
  before { Current.company = company }

  it "defaults to the regular type" do
    expect(create(:customer, company: company).customer_type).to eq("regular")
  end

  it "validates customer_type" do
    c = build(:customer, company: company, customer_type: "bogus")
    expect(c).not_to be_valid
    expect(c.errors[:customer_type]).to be_present
  end

  it "#commercial? reflects the type" do
    expect(build(:customer, customer_type: "commercial").commercial?).to be(true)
    expect(build(:customer, customer_type: "regular").commercial?).to be(false)
  end

  describe "#effective_discount_percent" do
    let(:tier) { PriceTier.create!(company: company, name: "Gold", discount_percent: 10) }

    it "is 0 with no tier and no override" do
      expect(create(:customer, company: company).effective_discount_percent).to eq(0)
    end

    it "uses the tier discount when no override is set" do
      c = create(:customer, company: company, price_tier: tier)
      expect(c.effective_discount_percent).to eq(10)
    end

    it "lets a per-customer override win over the tier" do
      c = create(:customer, company: company, price_tier: tier, discount_override_percent: 15)
      expect(c.effective_discount_percent).to eq(15)
    end

    it "rejects an override outside 0..100" do
      expect(build(:customer, discount_override_percent: 120)).not_to be_valid
    end
  end

  describe "#credit_status_for" do
    let(:customer) do
      create(:customer, company: company, customer_type: "commercial",
        credit_warning_limit_cents: 100_000, credit_hard_limit_cents: 150_000)
    end

    it "is :ok within the warning limit" do
      expect(customer.credit_status_for(80_000)).to eq(:ok)
    end

    it "is :warning past the warning limit but within hard" do
      expect(customer.credit_status_for(120_000)).to eq(:warning)
    end

    it "is :blocked past the hard limit" do
      expect(customer.credit_status_for(160_000)).to eq(:blocked)
    end

    it "is :ok when no limits are configured" do
      plain = create(:customer, company: company, customer_type: "commercial")
      expect(plain.credit_status_for(9_999_999)).to eq(:ok)
    end
  end
end
