# frozen_string_literal: true

require "rails_helper"

# Prices a self-order cart from the database only, with the same rules as the POS.
RSpec.describe Orders::QuoteService do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:burger) { create(:menu_item, company: company, name: "Burger", base_price_cents: 10_000) }
  let(:size) { ModifierGroup.create!(company: company, name: "Size", required: true, multi_select: false) }
  let!(:single) { size.modifiers.create!(company: company, name: "Single", price_adjustment_cents: 0) }
  let!(:double) { size.modifiers.create!(company: company, name: "Double", price_adjustment_cents: 4_000) }
  let(:extras) { ModifierGroup.create!(company: company, name: "Extras", multi_select: true) }
  let!(:cheese) { extras.modifiers.create!(company: company, name: "Cheese", price_adjustment_cents: 500) }
  let!(:bacon) { extras.modifiers.create!(company: company, name: "Bacon", price_adjustment_cents: 1_000) }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: burger, available: true)
    burger.menu_item_modifier_groups.create!(modifier_group: size, position: 1)
    burger.menu_item_modifier_groups.create!(modifier_group: extras, position: 2)
  end

  def quote(items, fee: 0)
    described_class.call(location: branch, items: items, delivery_fee_cents: fee)
  end

  it "prices items, choices, quantity and the delivery fee from the database" do
    result = quote([{ menu_item_id: burger.id, modifier_ids: [double.id, cheese.id, bacon.id], quantity: 2 }],
                   fee: 2_000)

    expect(result).to be_ok
    expect(result.subtotal_cents).to eq((10_000 + 4_000 + 500 + 1_000) * 2)
    expect(result.total_cents).to eq(31_000 + 2_000)
    expect(result.snapshot["lines"].first["modifiers"].map { |m| m["name"] }).to contain_exactly("Double", "Cheese", "Bacon")
  end

  it "uses the branch price override" do
    LocationMenuItem.find_by!(location: branch, menu_item: burger).update!(price_override_cents: 12_000)

    expect(quote([{ menu_item_id: burger.id, modifier_ids: [single.id] }]).subtotal_cents).to eq(12_000)
  end

  it "applies the live promo for the chosen size only" do
    create(:menu_promo, company: company, menu_item: burger, modifier: double, promo_price_cents: 11_000)

    single_line = quote([{ menu_item_id: burger.id, modifier_ids: [single.id] }])
    double_line = quote([{ menu_item_id: burger.id, modifier_ids: [double.id], quantity: 2 }])

    expect(single_line.discount_cents).to eq(0)
    expect(double_line.discount_cents).to eq((14_000 - 11_000) * 2)
  end

  it "drops choices that belong to another item" do
    other = ModifierGroup.create!(company: company, name: "Drink size")
    large = other.modifiers.create!(company: company, name: "Large", price_adjustment_cents: 99_000)

    result = quote([{ menu_item_id: burger.id, modifier_ids: [single.id, large.id] }])

    expect(result).to be_ok
    expect(result.subtotal_cents).to eq(10_000)
  end

  it "refuses a line with an empty required group" do
    result = quote([{ menu_item_id: burger.id, modifier_ids: [cheese.id] }])

    expect(result).not_to be_ok
    expect(result.errors).to eq(0 => :required_choice)
  end

  it "refuses two picks in a single-choice group" do
    expect(quote([{ menu_item_id: burger.id, modifier_ids: [single.id, double.id] }]).errors)
      .to eq(0 => :single_choice)
  end

  it "refuses an item that is off at this branch" do
    LocationMenuItem.find_by!(location: branch, menu_item: burger).update!(available: false)

    expect(quote([{ menu_item_id: burger.id, modifier_ids: [single.id] }]).errors).to eq(0 => :unavailable)
  end

  it "refuses absurd quantities" do
    expect(quote([{ menu_item_id: burger.id, modifier_ids: [single.id], quantity: 500 }]).errors)
      .to eq(0 => :bad_quantity)
  end

  it "is not ok for an empty cart" do
    expect(quote([])).not_to be_ok
  end
end
