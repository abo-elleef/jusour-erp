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

  it "counts modifier recipes, signed, times the line quantity" do
    expect(Accounting::ModifierRecipeCost.by_menu_item(OrderItem.all)).to eq(burger.id => 700)
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
