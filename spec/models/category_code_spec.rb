# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category, type: :model do
  describe "code" do
    it "auto-derives a code from the name on create" do
      cat = Category.create!(name: "Burgers", position: 1)
      expect(cat.code).to eq("BURG")
    end

    it "dedupes the derived code within the company" do
      first = Category.create!(name: "Burgers", position: 1)
      second = Category.create!(name: "Burritos", position: 2) # also "BURR"? no — "BURR"
      third = Category.create!(name: "Burgers Deluxe", position: 3) # "BURG" taken → "BURG2"
      expect(first.code).to eq("BURG")
      expect(second.code).to eq("BURR")
      expect(third.code).to eq("BURG2")
    end

    it "falls back to CAT when the name has no latin letters (e.g. Arabic)" do
      cat = Category.create!(name: "مشروبات", position: 1)
      expect(cat.code).to eq("CAT")
    end

    it "accepts a custom code and rejects duplicates (case-insensitive)" do
      Category.create!(name: "Drinks", code: "DRK", position: 1)
      dup = Category.new(name: "Cold Drinks", code: "drk", position: 2)
      expect(dup).not_to be_valid
      expect(dup.errors[:code]).to be_present
    end

    it "rejects a non-alphanumeric code" do
      cat = Category.new(name: "Sides", code: "SI-DE", position: 1)
      expect(cat).not_to be_valid
      expect(cat.errors[:code]).to be_present
    end
  end

  describe "recoding menu items when the category code changes" do
    let(:category) { Category.create!(name: "Burgers", code: "BURG", position: 1) }

    it "swaps the prefix on auto-coded items, keeping the sequence" do
      a = create(:menu_item, category: category) # BURG-001
      b = create(:menu_item, category: category) # BURG-002
      expect([a.code, b.code]).to eq(%w[BURG-001 BURG-002])

      category.update!(code: "BEEF")

      expect(a.reload.code).to eq("BEEF-001")
      expect(b.reload.code).to eq("BEEF-002")
    end

    it "leaves custom codes that don't match the old prefix untouched" do
      custom = create(:menu_item, category: category, code: "SPECIAL-9")

      category.update!(code: "BEEF")

      expect(custom.reload.code).to eq("SPECIAL-9")
    end

    it "does not touch items in other categories" do
      other = Category.create!(name: "Drinks", code: "DRK", position: 2)
      drink = create(:menu_item, category: other) # DRK-001

      category.update!(code: "BEEF")

      expect(drink.reload.code).to eq("DRK-001")
    end
  end
end
