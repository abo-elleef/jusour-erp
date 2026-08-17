# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ingredient units and conversion", type: :model do
  let(:category) { IngredientCategory.create!(name: "Oils", position: 1, company: Current.company) }
  let(:oil) do
    Ingredient.create!(name: "Oil", ingredient_category: category, unit: "ml",
      reorder_threshold: 1, cost_per_unit_cents: 0, quantity_on_hand: 0, company: Current.company)
  end

  describe "IngredientUnit validations" do
    it "requires the unit to differ from the base unit" do
      iu = oil.ingredient_units.build(unit: "ml", base_units_per_unit: 1, company: Current.company)
      expect(iu).not_to be_valid
      expect(iu.errors[:unit]).to be_present
    end

    it "requires a positive factor and a known unit, unique per ingredient" do
      expect(oil.ingredient_units.build(unit: "gallons", base_units_per_unit: 0, company: Current.company)).not_to be_valid
      expect(oil.ingredient_units.build(unit: "nope", base_units_per_unit: 5, company: Current.company)).not_to be_valid

      oil.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, company: Current.company)
      dup = oil.ingredient_units.build(unit: "gallons", base_units_per_unit: 3785, company: Current.company)
      expect(dup).not_to be_valid
    end

    it "allows only one purchase unit per ingredient" do
      first = oil.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, purchase_unit: true, company: Current.company)
      second = oil.ingredient_units.create!(unit: "liters", base_units_per_unit: 1000, purchase_unit: true, company: Current.company)

      expect(first.reload.purchase_unit?).to be(false)
      expect(second.reload.purchase_unit?).to be(true)
      expect(oil.purchase_unit).to eq("liters")
    end
  end

  describe "conversion helpers" do
    before { oil.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, company: Current.company) }

    it "lists base unit first, then alternates" do
      expect(oil.available_units).to eq(%w[ml gallons])
    end

    it "converts to and from the base unit" do
      expect(oil.to_base(2, "gallons")).to eq(7570)
      expect(oil.to_base(500, "ml")).to eq(500)
      expect(oil.to_base(500, nil)).to eq(500)
      expect(oil.from_base(7570, "gallons")).to eq(2)
    end

    it "accepts translated unit labels (e.g. Arabic show/forms)" do
      I18n.with_locale(:ar) do
        expect(oil.to_base(2, "جالون")).to eq(7570)
        expect(oil.from_base(7570, "جالون")).to eq(2)
        expect(oil.to_base(100, "مل")).to eq(100)
      end
    end

    it "raises for an unknown unit" do
      expect { oil.to_base(1, "drums") }.to raise_error(ArgumentError)
    end
  end

  describe "base unit change" do
    it "allows changing the base unit even when the ingredient has stock" do
      oil.update_columns(quantity_on_hand: 100)
      oil.reload
      expect(oil.update(unit: "liters")).to be(true)
      expect(oil.reload.unit).to eq("liters")
    end

    it "allows changing the base unit while unused" do
      expect(oil.update(unit: "liters")).to be(true)
    end

    it "clears alternate units when the base unit changes" do
      oil.ingredient_units.create!(unit: "gallons", base_units_per_unit: 3785, company: Current.company)
      expect(oil.update(unit: "liters")).to be(true)
      expect(oil.reload.ingredient_units).to be_empty
    end
  end
end
