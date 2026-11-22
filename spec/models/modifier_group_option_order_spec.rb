# frozen_string_literal: true

require "rails_helper"

RSpec.describe ModifierGroup, "option order" do
  let(:company) { create(:company) }
  let(:group) { described_class.create!(company: company, name: "Extras") }

  before { Current.company = company }

  def option(name, cents, position)
    group.modifiers.create!(company: company, name: name, price_adjustment_cents: cents, position: position)
  end

  it "follows the sort order first, then cheapest, then name" do
    option("Cheese", 1000, 1)
    option("Bacon", 1000, 1)
    option("No onion", 0, 1)
    option("Egg", 500, 1)
    option("Sauce on side", 2000, 0)

    expected = ["Sauce on side", "No onion", "Egg", "Bacon", "Cheese"]
    expect(group.reload.modifiers.map(&:name)).to eq(expected)
    expect(described_class.includes(:modifiers).find(group.id).modifiers.map(&:name)).to eq(expected)
  end
end
