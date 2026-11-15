# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderItem do
  describe ".in_menu_order" do
    let(:drinks) { Category.new(name: "Drinks", position: 2) }
    let(:burgers) { Category.new(name: "Burgers", position: 1) }
    let(:unpositioned) { Category.new(name: "Aaa", position: nil) }

    def line(name, category, created_at: Time.zone.parse("2026-11-15 12:00"))
      described_class.new(menu_item: MenuItem.new(name: name, category: category), created_at: created_at)
    end

    def combo_line(name)
      described_class.new(combo: Combo.new(name: name), created_at: Time.zone.parse("2026-11-15 12:00"))
    end

    it "groups by category in the menu's order, A→Z by name inside each, combos last" do
      items = [
        combo_line("Family box"),
        line("Water", drinks),
        line("Zinger", burgers),
        line("Cola", drinks),
        line("Beef", burgers),
        line("Fries", unpositioned)
      ]

      expect(described_class.in_menu_order(items).map(&:display_name))
        .to eq(["Beef", "Zinger", "Cola", "Water", "Fries", "Family box"])
    end

    it "keeps two lines of the same item in the order they were added" do
      first = line("Beef", burgers, created_at: Time.zone.parse("2026-11-15 12:00"))
      second = line("Beef", burgers, created_at: Time.zone.parse("2026-11-15 12:05"))

      expect(described_class.in_menu_order([second, first])).to eq([first, second])
    end
  end
end
