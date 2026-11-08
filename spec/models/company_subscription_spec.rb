# frozen_string_literal: true

require "rails_helper"

RSpec.describe Company, "subscription", type: :model do
  let(:today) { Date.new(2026, 11, 8) }
  let(:company) { build(:company) }

  def status_for(paid_until, active: true)
    company.assign_attributes(paid_until: paid_until, active: active)
    company.subscription_status(today)
  end

  it "has no expiry when paid_until is blank" do
    expect(status_for(nil)).to eq(:ok)
  end

  it "is :ok well before the date" do
    expect(status_for(today + 30)).to eq(:ok)
  end

  it "warns in the last week, including the final day" do
    expect(status_for(today + 7)).to eq(:expiring)
    expect(status_for(today)).to eq(:expiring)
  end

  it "keeps working through the grace period" do
    expect(status_for(today - 1)).to eq(:grace)
    expect(status_for(today - Company::SUBSCRIPTION_GRACE_DAYS)).to eq(:grace)
    expect(company.access_blocked?).to be(false)
  end

  it "locks after the grace period" do
    expect(status_for(today - Company::SUBSCRIPTION_GRACE_DAYS - 1)).to eq(:expired)
    expect(company.access_blocked?).to be(true)
  end

  it "is suspended, and blocked, when inactive regardless of date" do
    expect(status_for(today + 365, active: false)).to eq(:suspended)
    expect(company.access_blocked?).to be(true)
  end

  describe "#extend_subscription!" do
    it "extends from today when already expired" do
      company = create(:company, paid_until: Date.current - 40)
      company.extend_subscription!(months: 1)
      expect(company.paid_until).to eq(Date.current >> 1)
    end

    it "extends from the current expiry when renewing early" do
      expiry = Date.current + 10
      company = create(:company, paid_until: expiry)
      company.extend_subscription!(months: 12)
      expect(company.paid_until).to eq(expiry >> 12)
    end

    it "starts from today when there was no expiry" do
      company = create(:company, paid_until: nil)
      company.extend_subscription!(months: 3)
      expect(company.paid_until).to eq(Date.current >> 3)
    end
  end
end
