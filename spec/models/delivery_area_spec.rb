# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliveryArea do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }

  before { Current.company = company }

  it "is valid with a name and a branch" do
    area = described_class.new(location: branch, name: "Maadi", fee_cents: 2500)
    expect(area).to be_valid
    expect(area.company).to eq(company)
  end

  it "treats a blank fee as free delivery, not a missing value" do
    area = described_class.new(location: branch, name: "Zamalek", fee_pounds: "")
    expect(area.fee_cents).to be_nil
    expect(area).to be_valid
    expect(area.fee_cents).to eq(0)
  end

  it "reads a fee in pounds" do
    area = described_class.create!(location: branch, name: "Dokki", fee_pounds: "17.50")
    expect(area.fee_cents).to eq(1750)
  end

  it "refuses a negative fee" do
    area = described_class.new(location: branch, name: "Giza", fee_cents: -1)
    expect(area).not_to be_valid
    expect(area.errors[:fee_cents]).to be_present
  end

  it "needs a name that is unique within the branch, ignoring case" do
    described_class.create!(location: branch, name: "Maadi")
    expect(described_class.new(location: branch, name: "maadi")).not_to be_valid
    expect(described_class.new(location: create(:location, company: company), name: "Maadi")).to be_valid
  end

  it "belongs only to a branch, not a central kitchen" do
    kitchen = create(:location, :central_kitchen, company: company)
    area = described_class.new(location: kitchen, name: "Anywhere")
    expect(area).not_to be_valid
    expect(area.errors[:location]).to be_present
  end

  it "shows the Arabic name in Arabic when there is one" do
    area = described_class.new(name: "Maadi", name_ar: "المعادي")
    expect(area.display_name(:ar)).to eq("المعادي")
    expect(area.display_name(:en)).to eq("Maadi")
    expect(described_class.new(name: "Maadi").display_name(:ar)).to eq("Maadi")
  end

  it "is removed with its branch" do
    described_class.create!(location: branch, name: "Maadi")
    expect { branch.destroy }.to change(described_class, :count).by(-1)
  end

  it "orders by position, then name, and filters to active ones" do
    b = described_class.create!(location: branch, name: "B", position: 1)
    a = described_class.create!(location: branch, name: "A", position: 1)
    first = described_class.create!(location: branch, name: "Z", position: 0)
    described_class.create!(location: branch, name: "Off", position: 0, active: false)
    expect(branch.delivery_areas.active.ordered).to eq([first, a, b])
  end
end
