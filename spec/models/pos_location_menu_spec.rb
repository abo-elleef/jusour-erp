# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS location menu" do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, name: "Downtown") }
  let(:category) { create(:category, company: company) }
  let!(:burger) { create(:menu_item, company: company, category: category, name: "Burger", available: true) }
  let!(:fries) { create(:menu_item, company: company, category: category, name: "Fries", available: true) }

  before { Current.company = company }

  describe MenuItem do
    it "includes items without a location record" do
      expect(MenuItem.available_at_location(branch)).to contain_exactly(burger, fries)
    end

    it "excludes items explicitly disabled at the branch" do
      create(:location_menu_item, location: branch, menu_item: fries, available: false)

      expect(MenuItem.available_at_location(branch)).to contain_exactly(burger)
    end

    it "includes items explicitly enabled at the branch" do
      create(:location_menu_item, location: branch, menu_item: burger, available: true)

      expect(MenuItem.available_at_location(branch)).to contain_exactly(burger, fries)
    end

    it "uses branch price override when set" do
      create(:location_menu_item, location: branch, menu_item: burger, available: true, price_override_cents: 1299)

      expect(burger.price_cents_at(branch)).to eq(1299)
      expect(burger.price_cents_at(branch)).not_to eq(burger.base_price_cents)
    end
  end

  describe Combo do
    let!(:combo) do
      combo = Combo.create!(company: company, name: "Meal", price_cents: 1500, active: true)
      combo.combo_items.create!(menu_item: burger, quantity: 1)
      combo.combo_items.create!(menu_item: fries, quantity: 1)
      combo
    end

    it "is available when all items are available at the branch" do
      expect(Combo.available_at_location(branch)).to contain_exactly(combo)
    end

    it "is hidden when any item is disabled at the branch" do
      create(:location_menu_item, location: branch, menu_item: fries, available: false)

      expect(Combo.available_at_location(branch)).to be_empty
    end
  end
end
