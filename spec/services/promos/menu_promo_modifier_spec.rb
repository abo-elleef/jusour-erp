# frozen_string_literal: true

require "rails_helper"

# A promo can target one choice of an item, e.g. only the "Double" size.
RSpec.describe "Choice-specific menu promos" do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company) }
  let(:user) { create(:user, company: company) }
  let(:category) { create(:category, company: company) }
  let(:item) { create(:menu_item, company: company, category: category, base_price_cents: 12_000, available: true) }
  let(:group) { ModifierGroup.create!(company: company, name: "Size", required: true) }
  let(:single) { group.modifiers.create!(name: "Single", price_adjustment_cents: 0) }
  let(:double) { group.modifiers.create!(name: "Double", price_adjustment_cents: 2_000) }
  let(:order) { create(:order, company: company, user: user, location: branch, status: "draft") }

  before do
    Current.company = company
    create(:location_menu_item, location: branch, menu_item: item, available: true)
    item.menu_item_modifier_groups.create!(modifier_group: group, position: 1)
    single
    double
  end

  def promo(**attrs)
    create(:menu_promo, { company: company, menu_item: item, starts_at: 1.hour.ago, ends_at: 1.day.from_now }.merge(attrs))
  end

  def line_with(modifier, quantity: 1)
    line = order.order_items.create!(menu_item: item, quantity: quantity, unit_price_cents: 12_000)
    line.order_item_modifiers.create!(modifier: modifier, name: modifier.name,
                                      price_adjustment_cents: modifier.price_adjustment_cents)
    Promos::SyncOrderItemDiscount.call(order_item: line)
    line
  end

  describe MenuPromo do
    it "measures the promo price against the item plus the choice's adjustment" do
      expect(promo(modifier: double, promo_price_cents: 13_000).list_price_cents_at(branch)).to eq(14_000)
    end

    it "rejects a price at or above the choice's own price" do
      record = build(:menu_promo, company: company, menu_item: item, modifier: double, promo_price_cents: 14_000,
                                  starts_at: 1.hour.ago, ends_at: 1.day.from_now)
      expect(record).not_to be_valid
      expect(record.errors[:promo_price_cents]).to be_present
    end

    it "rejects a choice that is not on the item" do
      other = ModifierGroup.create!(company: company, name: "Drinks").modifiers.create!(name: "Cola", price_adjustment_cents: 0)
      record = build(:menu_promo, company: company, menu_item: item, modifier: other, promo_price_cents: 10_000,
                                  starts_at: 1.hour.ago, ends_at: 1.day.from_now)
      expect(record).not_to be_valid
      expect(record.errors[:modifier_id]).to be_present
    end
  end

  describe Promos::SyncOrderItemDiscount do
    it "discounts the Double only" do
      promo(modifier: double, promo_price_cents: 13_000)

      double_line = line_with(double, quantity: 2)
      single_line = line_with(single)

      expect(order.order_discounts.find_by!(order_item: double_line).amount_cents).to eq(2_000)
      expect(order.order_discounts.find_by(order_item: single_line)).to be_nil
    end

    it "keeps whole-item promos applying to every choice" do
      promo(promo_price_cents: 10_000)

      expect(order.order_discounts.find_by!(order_item: line_with(single)).amount_cents).to eq(2_000)
      expect(order.order_discounts.find_by!(order_item: line_with(double)).amount_cents).to eq(2_000)
    end

    it "prefers the choice-specific promo over a whole-item one" do
      promo(promo_price_cents: 11_000)
      specific = promo(modifier: double, promo_price_cents: 12_500)

      discount = order.order_discounts.find_by!(order_item: line_with(double))
      expect(discount.menu_promo_id).to eq(specific.id)
      expect(discount.amount_cents).to eq(1_500)
    end
  end

  describe Menus::ActivePromo do
    it "shows the choice-specific promo on the card with the choice's prices" do
      promo(modifier: double, promo_price_cents: 13_000)

      card = described_class.index_for(menu_items: [item], location: branch)[item.id]
      expect(card.modifier_name).to eq("Double")
      expect(card.list_price_cents).to eq(14_000)
      expect(card.promo_price_cents).to eq(13_000)
    end

    it "lists every promo in priority order for the offline register" do
      whole = promo(promo_price_cents: 11_000)
      specific = promo(modifier: double, promo_price_cents: 12_500)

      ids = described_class.new(location: branch).all_for_item(item).map { |row| row.promo.id }
      expect(ids).to eq([specific.id, whole.id])
    end
  end
end
