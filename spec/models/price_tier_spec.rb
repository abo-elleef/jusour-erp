# frozen_string_literal: true

require "rails_helper"

RSpec.describe PriceTier, type: :model do
  let(:company) { create(:company) }
  before { Current.company = company }

  it "is valid with a name and a discount in 0..100" do
    expect(PriceTier.new(company: company, name: "Gold", discount_percent: 12.5)).to be_valid
  end

  it "requires a name, unique per company" do
    PriceTier.create!(company: company, name: "Gold", discount_percent: 10)
    dup = PriceTier.new(company: company, name: "gold", discount_percent: 5)
    expect(dup).not_to be_valid
    expect(dup.errors[:name]).to be_present
  end

  it "rejects a discount outside 0..100" do
    expect(PriceTier.new(company: company, name: "Bad", discount_percent: 150)).not_to be_valid
    expect(PriceTier.new(company: company, name: "Bad2", discount_percent: -1)).not_to be_valid
  end
end
