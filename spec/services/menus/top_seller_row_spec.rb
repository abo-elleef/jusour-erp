# frozen_string_literal: true

require "rails_helper"

# The "Most sold" row: pinned items first in the manager's order, then the
# branch's best sellers, each screen showing only what that screen sells.
RSpec.describe Menus::TopSellerRow do
  let(:company) { create(:company) }
  let(:branch) { create(:location, company: company, pos_top_sellers_enabled: true, online_top_sellers_enabled: true) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:best) { create(:menu_item, company: company, name: "Best") }
  let(:second) { create(:menu_item, company: company, name: "Second") }
  let(:pinned) { create(:menu_item, company: company, name: "Pinned") }

  before do
    Current.company = company
    [best, second, pinned].each { |item| create(:location_menu_item, location: branch, menu_item: item, available: true) }
    sell(best, 9)
    sell(second, 5)
  end

  def sell(item, quantity)
    order = create(:order, user: cashier, location: branch, status: "completed", placed_at: 1.day.ago)
    create(:order_item, order: order, menu_item: item, quantity: quantity)
  end

  def row(channel)
    menu = Menus::ForLocation.call(location: branch, channel: channel)
    described_class.call(location: branch, channel: channel, menu_items: menu.menu_items).map(&:name)
  end

  it "fills the row from sales when nothing is pinned" do
    expect(row(:pos)).to eq(%w[Best Second])
  end

  it "puts pinned items first, in order, without repeating them from sales" do
    branch.update!(top_seller_pinned_item_ids: [pinned.id, second.id])
    expect(row(:pos)).to eq(%w[Pinned Second Best])
  end

  it "is empty on a screen where the branch has it turned off" do
    branch.update!(pos_top_sellers_enabled: false)
    expect(row(:pos)).to be_empty
    expect(row(:public)).to eq(%w[Best Second])
  end

  it "leaves out items the screen does not sell, pinned or not" do
    pos_only = create(:category, company: company, menu_visibility: "pos")
    pinned.update!(category: pos_only)
    best.update!(category: pos_only)
    branch.update!(top_seller_pinned_item_ids: [pinned.id])

    expect(row(:public)).to eq(%w[Second])
    expect(row(:pos)).to eq(%w[Pinned Best Second])
  end

  it "holds at most the row size" do
    extra = create_list(:menu_item, Location::TOP_SELLERS_ROW_SIZE, company: company)
    extra.each { |item| create(:location_menu_item, location: branch, menu_item: item, available: true) }
    branch.update!(top_seller_pinned_item_ids: extra.map(&:id))

    expect(row(:pos).size).to eq(Location::TOP_SELLERS_ROW_SIZE)
    expect(row(:pos)).not_to include("Best")
  end
end
