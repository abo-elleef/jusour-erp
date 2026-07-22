# frozen_string_literal: true

require "rails_helper"

RSpec.describe IngredientCategory, type: :model do
  def category(name, **attrs)
    IngredientCategory.create!({ name: name, position: 1, active: true }.merge(attrs))
  end

  describe "name-derived code" do
    it "derives the code from the name on create" do
      expect(category("Proteins").code).to eq("PROTEINS")
    end

    it "keeps non-latin (Arabic) names meaningful" do
      expect(category("زيوت").code).to eq("زيوت")
    end

    it "dedupes a colliding derived code within the company" do
      first = category("Oils", position: 1)
      second = category("O.I.L.S", position: 2)
      expect(first.code).to eq("OILS")
      expect(second.code).to eq("OILS2")
    end
  end

  describe "renaming re-derives the code and cascades to ingredient codes" do
    it "swaps the prefix on the category's auto-coded ingredients" do
      cat = category("Proteins")
      a = create(:ingredient, ingredient_category: cat)
      b = create(:ingredient, ingredient_category: cat)
      expect([a.code, b.code]).to eq(%w[PROTEINS-001 PROTEINS-002])

      cat.update!(name: "Meats")

      expect(cat.reload.code).to eq("MEATS")
      expect(a.reload.code).to eq("MEATS-001")
      expect(b.reload.code).to eq("MEATS-002")
    end

    it "leaves custom ingredient codes (not matching the prefix) untouched" do
      cat = category("Proteins")
      custom = create(:ingredient, ingredient_category: cat, code: "SPECIAL-9")

      cat.update!(name: "Meats")

      expect(custom.reload.code).to eq("SPECIAL-9")
    end

    it "does not cascade when the name changes but the derived code doesn't" do
      cat = category("Oils")
      ing = create(:ingredient, ingredient_category: cat)
      cat.update!(name: "O.I.L.S") # still derives OILS

      expect(cat.reload.code).to eq("OILS")
      expect(ing.reload.code).to eq("OILS-001")
    end
  end
end
