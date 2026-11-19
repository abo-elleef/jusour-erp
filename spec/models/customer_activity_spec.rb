# frozen_string_literal: true

require "rails_helper"

RSpec.describe CustomerActivity, type: :model do
  let(:company) { create(:company, business_type: "distribution") }

  before { Current.company = company }

  let(:customer) { create(:customer, company: company, name: "Alpha Clinic") }

  it "requires a note" do
    activity = described_class.new(customer: customer, activity_type: "call", note: " ")

    expect(activity).not_to be_valid
    expect(activity.errors[:note]).to be_present
  end

  it "accepts only the rep-logged types, the same ones a lead logs" do
    expect(described_class::LOGGABLE_TYPES).to eq(LeadActivity::LOGGABLE_TYPES)
    expect(described_class.new(customer: customer, activity_type: "stage_change", note: "x")).not_to be_valid
    expect(described_class.new(customer: customer, activity_type: "whatsapp", note: "x")).to be_valid
  end

  it "defaults occurred_at to now and lists newest first" do
    old = described_class.create!(customer: customer, activity_type: "note", note: "old", occurred_at: 2.days.ago)
    fresh = described_class.create!(customer: customer, activity_type: "call", note: "new")

    expect(fresh.occurred_at).to be_within(5.seconds).of(Time.current)
    expect(customer.customer_activities.recent).to eq([fresh, old])
  end
end
