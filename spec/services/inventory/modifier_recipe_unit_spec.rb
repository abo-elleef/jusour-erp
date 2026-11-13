# frozen_string_literal: true

require "rails_helper"

# A beef ball stocked by the 20-piece batch: an extra ball on a "Double" must be
# 1 piece (0.05 batch), not 1 batch.
RSpec.describe "Modifier recipes in an alternate unit", type: :model do
  let(:category) { IngredientCategory.create!(name: "Meat", position: 1, company: Current.company) }
  let(:ball) do
    ing = Ingredient.create!(name: "Beef ball", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 2000, quantity_on_hand: 0, company: Current.company)
    ing.ingredient_units.create!(unit: "pieces", base_units_per_unit: 0.05, company: Current.company)
    ing
  end
  let(:menu_item) { create(:menu_item) }
  let(:group) { ModifierGroup.create!(company: Current.company, name: "Size") }
  let(:double) { group.modifiers.create!(company: Current.company, name: "Double", price_adjustment_cents: 500) }
  let(:location) { create(:location, company: Current.company) }

  describe "ModifierRecipe#base_quantity" do
    it "converts the recipe unit to the base unit" do
      mr = ModifierRecipe.create!(modifier: double, ingredient: ball, quantity: 1, unit: "pieces")
      expect(mr.base_quantity).to eq(BigDecimal("0.05"))
    end

    it "treats a blank unit as the base unit" do
      mr = ModifierRecipe.create!(modifier: double, ingredient: ball, quantity: 1)
      expect(mr.base_quantity).to eq(1)
    end

    it "keeps the sign" do
      mr = ModifierRecipe.create!(modifier: double, ingredient: ball, quantity: -2, unit: "pieces")
      expect(mr.base_quantity).to eq(BigDecimal("-0.1"))
    end

    it "rejects a unit the ingredient doesn't have" do
      expect(ModifierRecipe.new(modifier: double, ingredient: ball, quantity: 1, unit: "liters")).not_to be_valid
    end
  end

  context "with a Double sold twice" do
    before do
      ModifierRecipe.create!(modifier: double, ingredient: ball, quantity: 1, unit: "pieces")
      Recipe.create!(menu_item: menu_item, ingredient: ball, quantity_used: 1, unit: "pieces")
    end

    def sell(status:)
      order = create(:order, status: status, location: location, order_type: "table",
        created_at: Time.zone.now.change(hour: 12))
      line = create(:order_item, order: order, menu_item: menu_item, quantity: 2)
      line.order_item_modifiers.create!(modifier: double, name: "Double", price_adjustment_cents: 500)
      order
    end

    it "deducts one piece per Double from stock" do
      ball.update!(quantity_on_hand: 1)
      StockBatch.create!(ingredient: ball, location: location, quantity_received: 1,
        quantity_remaining: 1, cost_per_unit_cents: 2000, received_on: Date.current)

      Inventory::DeductStockService.new(sell(status: "submitted")).call

      # 2 sandwiches × (1 piece + 1 extra piece) = 4 pieces = 0.2 batch
      expect(ball.stock_batches.sum(:quantity_remaining).to_d).to eq(BigDecimal("0.8"))
    end

    it "costs and counts the converted quantity in the reports" do
      sell(status: "completed")

      # 2 × 0.05 batch × 2000 = 200 cents for the Doubles
      expect(Accounting::ModifierRecipeCost.by_menu_item(OrderItem.all)).to eq(menu_item.id => 200)

      row = Inventory::IngredientConsumptionService.new(Date.current, Date.current).call[:rows]
        .find { |r| r[:ingredient] == ball }
      expect(row[:theoretical]).to eq(BigDecimal("0.2")) # item 0.1 + Doubles 0.1
    end
  end
end
