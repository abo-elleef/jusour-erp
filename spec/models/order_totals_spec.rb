# frozen_string_literal: true

require "rails_helper"

# Pins the exact numbers Order#recalculate_totals! produces, so that making it
# cheaper (fewer queries) can never quietly change a total.
RSpec.describe Order, "#recalculate_totals!" do
  let(:user) { create(:user) }
  let(:company) { user.company }
  let(:order) { create(:order, user: user, order_type: "delivery") }

  let(:food_item) { create(:menu_item, company: company, tax_category: "food") }
  let(:drink_item) { create(:menu_item, company: company, tax_category: "beverage") }
  let(:boxed_item) { create(:menu_item, company: company, tax_category: "packaged") }

  let(:group) { ModifierGroup.create!(company: company, name: "Size") }
  let(:large) { Modifier.create!(modifier_group: group, name: "Large", price_adjustment_cents: 1_550) }
  let(:no_sauce) { Modifier.create!(modifier_group: group, name: "No sauce", price_adjustment_cents: -275) }

  def add_line(menu_item, unit_price_cents:, quantity:, modifiers: [])
    line = create(:order_item, order: order, menu_item: menu_item,
                               unit_price_cents: unit_price_cents, quantity: quantity)
    modifiers.each do |modifier|
      OrderItemModifier.create!(order_item: line, modifier: modifier, name: modifier.name,
                                price_adjustment_cents: modifier.price_adjustment_cents)
    end
    line
  end

  before do
    # Two rates on food, one on beverage, an inactive one that must be ignored,
    # and nothing on packaged. Rates chosen so per-line rounding matters.
    TaxRate.create!(name: "VAT", rate: 0.14, tax_category: "food", active: true)
    TaxRate.create!(name: "Service", rate: 0.0333, tax_category: "food", active: true)
    TaxRate.create!(name: "Drink VAT", rate: 0.105, tax_category: "beverage", active: true)
    TaxRate.create!(name: "Old", rate: 0.5, tax_category: "food", active: false)

    add_line(food_item, unit_price_cents: 4_999, quantity: 3, modifiers: [large, no_sauce]) # (4999+1550-275)*3 = 18822
    add_line(food_item, unit_price_cents: 1_234, quantity: 1)                              # 1234
    add_line(drink_item, unit_price_cents: 1_777, quantity: 2, modifiers: [large])         # (1777+1550)*2 = 6654
    add_line(boxed_item, unit_price_cents: 3_000, quantity: 1)                              # 3000, no tax
    OrderDiscount.create!(order: order, description: "Manager", amount_cents: 1_111)
    order.update!(delivery_fee_cents: 2_500)
  end

  it "keeps subtotal, discount, tax and total exactly as before" do
    order.recalculate_totals!
    order.reload

    expect(order.subtotal_cents).to eq(18_822 + 1_234 + 6_654 + 3_000)
    expect(order.discount_cents).to eq(1_111)
    # food: 18822*.14=2635.08→2635, 18822*.0333=626.77→627, 1234*.14=172.76→173,
    # 1234*.0333=41.09→41; beverage: 6654*.105=698.67→699; packaged: none.
    expect(order.tax_cents).to eq(2_635 + 627 + 173 + 41 + 699)
    expect(order.total_cents).to eq(29_710 - 1_111 + 4_175 + 0 + 2_500)
  end

  it "picks up a modifier added after an earlier recalculation" do
    order.recalculate_totals!
    line = order.order_items.find_by(unit_price_cents: 1_234)
    OrderItemModifier.create!(order_item: line, modifier: large, name: "Large", price_adjustment_cents: 1_550)

    order.recalculate_totals!
    expect(order.reload.subtotal_cents).to eq(29_710 + 1_550)
  end

  it "persists tax through Tax::CalculateService on its own (submit relies on it)" do
    Tax::CalculateService.call(order)
    expect(order.reload.tax_cents).to eq(4_175)
  end

  # Reads only: whether an UPDATE runs depends on whether a total changed.
  it "does not run more reads as lines are added" do
    order.recalculate_totals!
    count_queries = lambda do
      count = 0
      callback = lambda do |*, payload|
        count += 1 if payload[:sql].start_with?("SELECT") && payload[:name] != "SCHEMA" && !payload[:cached]
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { order.recalculate_totals! }
      count
    end
    before_count = count_queries.call

    3.times { add_line(food_item, unit_price_cents: 500, quantity: 1, modifiers: [large]) }
    expect(count_queries.call).to eq(before_count)
  end
end
