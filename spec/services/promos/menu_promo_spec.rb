# frozen_string_literal: true

require "rails_helper"

RSpec.describe Menus::ActivePromo do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, public_menu_enabled: true) }
  let(:category) { create(:category, company: company) }
  let(:menu_item) { create(:menu_item, company: company, category: category, base_price_cents: 2000, available: true) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: menu_item, available: true)
  end

  it "returns the active promo markdown for a location" do
    create(:menu_promo,
      company: company,
      menu_item: menu_item,
      promo_price_cents: 1500,
      starts_at: 1.hour.ago,
      ends_at: 2.days.from_now)

    result = described_class.for(menu_item: menu_item, location: branch)

    expect(result.list_price_cents).to eq(2000)
    expect(result.promo_price_cents).to eq(1500)
    expect(result.discount_cents).to eq(500)
  end

  it "prefers a branch-specific promo over company-wide" do
    create(:menu_promo,
      company: company,
      menu_item: menu_item,
      location: nil,
      promo_price_cents: 1800,
      starts_at: 1.hour.ago,
      ends_at: 2.days.from_now)
    create(:menu_promo,
      company: company,
      menu_item: menu_item,
      location: branch,
      promo_price_cents: 1200,
      starts_at: 1.hour.ago,
      ends_at: 2.days.from_now)

    result = described_class.for(menu_item: menu_item, location: branch)

    expect(result.promo_price_cents).to eq(1200)
  end

  it "ignores expired promos" do
    create(:menu_promo,
      company: company,
      menu_item: menu_item,
      promo_price_cents: 1000,
      starts_at: 3.days.ago,
      ends_at: 1.day.ago)

    expect(described_class.for(menu_item: menu_item, location: branch)).to be_nil
  end
end

RSpec.describe Promos::SyncOrderItemDiscount do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:user) { create(:user, company: company) }
  let(:category) { create(:category, company: company) }
  let(:menu_item) { create(:menu_item, company: company, category: category, base_price_cents: 2000) }
  let(:order) { create(:order, company: company, user: user, location: branch, status: "draft") }

  before { Current.company = company }

  it "creates an order discount for the promo markdown at list price" do
    create(:menu_promo,
      company: company,
      menu_item: menu_item,
      promo_price_cents: 1400,
      starts_at: 1.hour.ago,
      ends_at: 1.day.from_now)

    item = order.order_items.create!(menu_item: menu_item, quantity: 2, unit_price_cents: 2000)
    described_class.call(order_item: item)
    order.recalculate_totals!

    discount = order.order_discounts.promos.find_by!(order_item: item)
    expect(discount.amount_cents).to eq(1200)
    expect(order.discount_cents).to eq(1200)
    expect(order.subtotal_cents).to eq(4000)
  end

  it "updates the discount when quantity changes" do
    create(:menu_promo,
      company: company,
      menu_item: menu_item,
      promo_price_cents: 1500,
      starts_at: 1.hour.ago,
      ends_at: 1.day.from_now)

    item = order.order_items.create!(menu_item: menu_item, quantity: 1, unit_price_cents: 2000)
    described_class.call(order_item: item)
    item.update!(quantity: 3)
    described_class.call(order_item: item)

    expect(order.order_discounts.promos.find_by!(order_item: item).amount_cents).to eq(1500)
  end
end

RSpec.describe Combo do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:category) { create(:category, company: company) }
  let(:burger) { create(:menu_item, company: company, category: category, available: true) }
  let(:fries) { create(:menu_item, company: company, category: category, available: true) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: burger, available: true)
    create(:location_menu_item, location: branch, menu_item: fries, available: true)
  end

  it "hides scheduled combos outside their window" do
    combo = Combo.create!(company: company, name: "Meal", price_cents: 2500, active: true,
      starts_at: 2.days.from_now, ends_at: 5.days.from_now, highlight: true)
    combo.combo_items.create!(menu_item: burger, quantity: 1)
    combo.combo_items.create!(menu_item: fries, quantity: 1)

    expect(Combo.available_at_location(branch)).to be_empty
  end

  it "includes highlighted combos that are in window" do
    combo = Combo.create!(company: company, name: "Meal", price_cents: 2500, active: true,
      starts_at: 1.hour.ago, ends_at: 2.days.from_now, highlight: true)
    combo.combo_items.create!(menu_item: burger, quantity: 1)
    combo.combo_items.create!(menu_item: fries, quantity: 1)

    expect(Combo.available_at_location(branch)).to contain_exactly(combo)
    expect(combo.highlighted_now?).to eq(true)
  end
end
