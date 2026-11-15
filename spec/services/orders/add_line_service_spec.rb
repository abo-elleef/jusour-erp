# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::AddLineService do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:burger) { create(:menu_item, company: company, name: "Burger", base_price_cents: 10_000) }
  let(:extras) { ModifierGroup.create!(company: company, name: "Extras", multi_select: true) }
  let!(:cheese) { extras.modifiers.create!(company: company, name: "Cheese", price_adjustment_cents: 500) }
  let(:order) { Orders::CreateService.call(user: cashier, location: branch, order_type: "pickup") }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: burger, available: true)
    burger.menu_item_modifier_groups.create!(modifier_group: extras, position: 1)
  end

  def add(**attrs)
    line = Orders::ResolveLine.call(location: branch, menu_item_id: burger.id, **attrs)
    described_class.call(order: order, line: line)
  end

  it "saves the line with its choices at database prices" do
    item = add(modifier_ids: [cheese.id], quantity: 2)

    expect(item.unit_price_cents).to eq(10_000)
    expect(item.order_item_modifiers.map(&:price_adjustment_cents)).to eq([500])
    expect(item.line_total_cents).to eq(21_000)
  end

  it "merges the same item with the same choices and no note" do
    add(modifier_ids: [cheese.id])
    add(modifier_ids: [cheese.id], quantity: 2)
    add

    expect(order.order_items.count).to eq(2)
    expect(order.order_items.find_by(quantity: 3)).to be_present
  end

  it "keeps a line with a note separate" do
    add
    add(notes: "no onions")

    expect(order.order_items.count).to eq(2)
  end

  it "books the promo discount on the line" do
    create(:menu_promo, company: company, menu_item: burger, promo_price_cents: 8_000)

    add(quantity: 2)

    expect(order.order_discounts.sum(:amount_cents)).to eq(4_000)
  end
end
