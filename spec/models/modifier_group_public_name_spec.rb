# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModifierGroup, "public name" do
  let(:company) { create(:company) }

  before { Current.company = company }

  it "shows the public name to customers when it is filled in" do
    group = described_class.create!(company: company, name: "Spicy / not spicy", public_name: "Hot level")
    expect(group.display_name_for_public).to eq("Hot level")
  end

  it "falls back to the cashier name when the public name is blank" do
    group = described_class.create!(company: company, name: "Spicy / not spicy", public_name: "   ")
    expect(group.reload.public_name).to be_nil
    expect(group.display_name_for_public).to eq("Spicy / not spicy")
  end
end
