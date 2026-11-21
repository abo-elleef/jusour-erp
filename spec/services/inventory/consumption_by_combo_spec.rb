# frozen_string_literal: true

require "rails_helper"

# A modifier's own recipe (a Double's extra patty) is drawn from stock when the
# order completes; the cost figures must count it too.
RSpec.describe "Modifier recipes in cost figures" do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company, wages_account_code: 2501) }
  let(:location) { create(:location, company: company) }
  let(:today) { Date.current }
  let(:patty) { create(:ingredient, company: company, cost_per_unit_cents: 400) }
  let(:onion) { create(:ingredient, company: company, cost_per_unit_cents: 100) }
  let(:burger) { create(:menu_item, company: company, base_price_cents: 1000) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size") }
  let(:double) { size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 500) }
  let(:no_onion) { size.modifiers.create!(company: company, name: "No onion") }

  before do
    Current.company = company
    Recipe.create!(menu_item: burger, ingredient: patty, quantity_used: 1, unit: "kg")
    Recipe.create!(menu_item: burger, ingredient: onion, quantity_used: 1, unit: "kg")
    ModifierRecipe.create!(company: company, modifier: double, ingredient: patty, quantity: 1)
    ModifierRecipe.create!(company: company, modifier: no_onion, ingredient: onion, quantity: -1)

    order = create(:order, user: user, company: company, status: "completed", location: location,
      subtotal_cents: 4000, total_cents: 4000, created_at: Time.zone.now.change(hour: 12))
    plain = create(:order_item, order: order, menu_item: burger, quantity: 1, unit_price_cents: 1000)
    doubled = create(:order_item, order: order, menu_item: burger, quantity: 2, unit_price_cents: 1000)
    doubled.order_item_modifiers.create!(modifier: double, name: "Double", price_adjustment_cents: 500)
    plain.order_item_modifiers.create!(modifier: no_onion, name: "No onion", price_adjustment_cents: 0)
  end

  # Base: 3 burgers × (400 + 100) = 1500. Double: +400 × 2 = 800. No onion: −100 × 1.
  let(:expected_cents) { 1500 + 800 - 100 }

  it "counts item and modifier recipes, signed, times the line quantity" do
    expect(Inventory::ConsumptionByCombo.new(OrderItem.all).cost_cents_by_menu_item).to eq(burger.id => expected_cents)
  end

  it "adds them to the food cost report" do
    row = Accounting::FoodCostService.new(today, today).call[:items].find { |r| r[:item] == burger }
    expect(row[:cost_cents]).to eq(expected_cents)
  end

  it "adds them to the day's COGS row" do
    ExpenseCategory.create!(company: company, name: "COGS", category_type: "cogs", system_managed: true)
    Accounting::DailyCogsService.call(location: location, business_date: BusinessDay.for(Time.zone.now.change(hour: 12), location: location), user: user)
    cogs = Expense.find_by(source_record: location, is_auto_generated: true)
    expect(cogs.amount_cents).to eq(expected_cents)
  end

  it "adds them to theoretical ingredient usage" do
    rows = Inventory::IngredientConsumptionService.new(today, today).call[:rows].index_by { |r| r[:ingredient] }
    expect(rows[patty][:theoretical]).to eq(5) # 3 base + 2 from the Double
    expect(rows[onion][:theoretical]).to eq(2) # 3 base − 1 left off
  end
end

RSpec.describe "Recipe matrix rows in stock and cost figures" do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company, wages_account_code: 2501) }
  let(:location) { create(:location, company: company) }
  let(:today) { Date.current }
  let(:meat) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 30_000) }
  let(:sauce) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 5_000) }
  let(:hot_sauce) { create(:ingredient, company: company, unit: "kg", cost_per_unit_cents: 8_000) }
  let(:sandwich) { create(:menu_item, company: company) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size") }
  let(:double) { size.modifiers.create!(company: company, name: "Double") }
  let(:spice) { ModifierGroup.create!(company: company, name: "Spice") }
  let(:spicy) { spice.modifiers.create!(company: company, name: "Spicy") }
  let!(:order) do
    create(:order, user: user, company: company, status: "completed", location: location,
      subtotal_cents: 4000, total_cents: 4000, created_at: Time.zone.now.change(hour: 12))
  end

  before do
    Current.company = company
    Recipe.create!(menu_item: sandwich, ingredient: meat, quantity_used: 0.1, unit: "kg")
    Recipe.create!(menu_item: sandwich, ingredient: sauce, quantity_used: 0.02, unit: "kg")
    [size, spice].each { |g| MenuItemModifierGroup.create!(menu_item: sandwich, modifier_group: g, recipe_matrix: true) }
    row = CombinationRecipe.create!(menu_item: sandwich, modifier_ids: [double.id, spicy.id])
    row.lines.create!(ingredient: meat, quantity: 0.2)
    row.lines.create!(ingredient: hot_sauce, quantity: 0.04)
    line = create(:order_item, order: order, menu_item: sandwich, quantity: 3, unit_price_cents: 1000)
    line.order_item_modifiers.create!(modifier: spicy, name: "Spicy", price_adjustment_cents: 0)
    line.order_item_modifiers.create!(modifier: double, name: "Double", price_adjustment_cents: 0)
    create(:order_item, order: order, menu_item: sandwich, quantity: 1, unit_price_cents: 1000)
  end

  # 3 spicy Doubles from the row: meat 0.6, hot sauce 0.12. 1 plain: meat 0.1, sauce 0.02.
  let(:expected_cents) { 3 * (6_000 + 320) + (3_000 + 100) }

  it "costs and counts each line by its row" do
    combo = Inventory::ConsumptionByCombo.new(OrderItem.all)
    expect(combo.cost_cents_by_menu_item).to eq(sandwich.id => expected_cents)
    expect(combo.quantity_by_ingredient).to eq(meat.id => BigDecimal("0.7"), sauce.id => BigDecimal("0.02"),
                                               hot_sauce.id => BigDecimal("0.12"))
    row = Accounting::FoodCostService.new(today, today).call[:items].find { |r| r[:item] == sandwich }
    expect(row[:cost_cents]).to eq(expected_cents)
  end

  it "deducts stock by the row and the void restock puts the same back" do
    [meat, sauce, hot_sauce].each do |ing|
      ing.ingredient_locations.create!(location: location, quantity_on_hand: 5, reorder_threshold: 0)
    end
    Inventory::DeductStockService.new(order).call
    drawn = StockAdjustment.where(adjustment_type: "consumption").group(:ingredient_id).sum(:quantity_delta)
    expect(drawn.transform_values(&:to_d)).to eq(
      meat.id => BigDecimal("-0.7"), sauce.id => BigDecimal("-0.02"), hot_sauce.id => BigDecimal("-0.12")
    )

    back = Orders::UndoCompletionService.allocate.tap { |s| s.instance_variable_set(:@order, order) }
      .send(:ingredient_totals).transform_keys(&:id)
    expect(back).to eq(meat.id => BigDecimal("0.7"), sauce.id => BigDecimal("0.02"), hot_sauce.id => BigDecimal("0.12"))
  end
end
