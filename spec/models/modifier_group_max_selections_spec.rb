# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModifierGroup do
  let(:company) { create(:company) }

  before { Current.company = company }

  it "keeps a positive cap on a multi-select group" do
    group = described_class.create!(company: company, name: "Sauces", multi_select: true, max_selections: 3)
    expect(group.reload.max_selections).to eq(3)
  end

  it "drops the cap on a single-choice group" do
    group = described_class.create!(company: company, name: "Size", multi_select: false, max_selections: 3)
    expect(group.reload.max_selections).to be_nil
  end

  it "rejects zero or negative caps" do
    group = described_class.new(company: company, name: "Sauces", multi_select: true, max_selections: 0)
    expect(group).not_to be_valid
  end
end
