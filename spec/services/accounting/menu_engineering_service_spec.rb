# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::MenuEngineeringService do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company, wages_account_code: 2501) }
  let(:branch) { create(:location, company: company, name: "Maadi") }
  let(:other_branch) { create(:location, company: company, name: "Zamalek") }
  let(:mains) { create(:category, company: company, name: "Mains") }
  let(:sides) { create(:category, company: company, name: "Sides") }
  let(:today) { Date.current }

  def item(name, price:, cost:, category: mains)
    menu_item = create(:menu_item, company: company, name: name, base_price_cents: price, category: category)
    if cost
      ingredient = create(:ingredient, company: company, cost_per_unit_cents: cost)
      Recipe.create!(menu_item: menu_item, ingredient: ingredient, quantity_used: 1, unit: "kg")
    end
    menu_item
  end

  def order(location: branch, status: "completed")
    create(:order, user: user, company: company, location: location, status: status,
                   subtotal_cents: 0, total_cents: 0, created_at: Time.zone.now.change(hour: 12))
  end

  def sell(order, menu_item, units)
    create(:order_item, order: order, menu_item: menu_item, quantity: units, unit_price_cents: menu_item.base_price_cents)
  end

  let!(:burger) { item("Burger", price: 1000, cost: 300) }            # margin 700
  let!(:fries)  { item("Fries",  price: 400,  cost: 300, category: sides) } # margin 100
  let!(:steak)  { item("Steak",  price: 2000, cost: 500) }            # margin 1500
  let!(:salad)  { item("Salad",  price: 500,  cost: 400, category: sides) } # margin 100
  let!(:water)  { item("Water",  price: 600,  cost: nil, category: sides) }

  before do
    Current.company = company
    o = order
    sell(o, burger, 10)
    sell(o, fries, 10)
    sell(o, steak, 2)
    sell(o, salad, 2)
    sell(o, water, 20)
    sell(order(status: "cancelled"), salad, 50) # never counted
  end

  def by_name(result) = result.rows.index_by(&:name)

  it "places every item in its quadrant against the 70% popularity rule and the weighted average margin" do
    result = described_class.new(today, today).call

    # 4 costed items: popular = 70% × 1/4 = 17.5% of 24 units; average margin = 11,200 / 24.
    expect(result.popularity_threshold_pct).to eq(17.5)
    expect(result.avg_unit_margin_cents).to eq(467)
    rows = by_name(result)
    expect(rows.transform_values(&:klass)).to eq(
      "Burger" => "star", "Fries" => "plowhorse", "Steak" => "puzzle", "Salad" => "dog", "Water" => "no_cost"
    )
    expect(result.counts).to eq("star" => 1, "plowhorse" => 1, "puzzle" => 1, "dog" => 1, "no_cost" => 1)

    burger_row = rows["Burger"]
    expect(burger_row.units).to eq(10)
    expect(burger_row.sales_cents).to eq(10_000)
    expect(burger_row.cost_cents).to eq(3_000)
    expect(burger_row.unit_margin_cents).to eq(700)
    expect(burger_row.mix_pct.round(1)).to eq(41.7)
    expect(burger_row.food_cost_pct).to eq(30.0)
  end

  it "keeps items without recipe cost out of the matrix and the thresholds" do
    water_row = by_name(described_class.new(today, today).call)["Water"]
    expect(water_row.mix_pct).to be_nil
    expect(water_row.costed?).to be(false)
  end

  it "agrees with the Food cost report on cost per item" do
    food = Accounting::FoodCostService.new(today, today).call[:items].to_h { |r| [r[:item].name, r[:cost_cents]] }
    ours = described_class.new(today, today).call.rows.to_h { |r| [r.name, r.cost_cents] }
    expect(ours.slice("Burger", "Fries", "Steak", "Salad")).to eq(food.slice("Burger", "Fries", "Steak", "Salad"))
  end

  it "classifies within the chosen category" do
    result = described_class.new(today, today, category_id: sides.id).call
    # Fries 10 units / Salad 2 units, both margin 100: threshold 35%, average 100.
    expect(by_name(result).transform_values(&:klass)).to eq("Fries" => "star", "Salad" => "puzzle", "Water" => "no_cost")
  end

  it "filters to one branch" do
    sell(order(location: other_branch), steak, 30)
    result = described_class.new(today, today, location_id: other_branch.id).call
    expect(result.rows.map(&:name)).to eq(["Steak"])
    expect(result.rows.first.units).to eq(30)
  end

  it "narrows the rows to one class but keeps every count" do
    result = described_class.new(today, today).call(klass: "dog")
    expect(result.rows.map(&:name)).to eq(["Salad"])
    expect(result.counts.values.sum).to eq(5)
    expect(result.totals[:units]).to eq(2)
  end

  it "sorts by any column and falls back on an unknown key" do
    expect(described_class.new(today, today).call(sort: "unit_margin", direction: "desc").rows.first.name).to eq("Steak")
    expect(described_class.new(today, today).call(sort: "name", direction: "asc").rows.map(&:name))
      .to eq(%w[Burger Fries Salad Steak Water])
    expect { described_class.new(today, today).call(sort: "DROP TABLE") }.not_to raise_error
  end

  it "counts modifier prices in sales" do
    size = ModifierGroup.create!(company: company, name: "Size")
    large = size.modifiers.create!(company: company, name: "Large", price_adjustment_cents: 200)
    line = sell(order, burger, 1)
    line.order_item_modifiers.create!(modifier: large, name: "Large", price_adjustment_cents: 200)

    expect(by_name(described_class.new(today, today).call)["Burger"].sales_cents).to eq(10_000 + 1_200)
  end
end
