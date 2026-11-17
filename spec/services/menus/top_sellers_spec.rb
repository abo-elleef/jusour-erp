# frozen_string_literal: true

require "rails_helper"

RSpec.describe Menus::TopSellers do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company) }
  let(:branch) { create(:location, company: company, name: "Main") }
  let(:other_branch) { create(:location, company: company, name: "Other") }
  let(:burger) { create(:menu_item, company: company, name: "Burger") }
  let(:fries) { create(:menu_item, company: company, name: "Fries") }
  let(:cola) { create(:menu_item, company: company, name: "Cola") }

  before { Current.company = company }

  def sale(item, quantity:, location: branch, status: "completed", placed_at: 1.day.ago)
    order = create(:order, user: user, location: location, status: status, placed_at: placed_at)
    create(:order_item, order: order, menu_item: item, quantity: quantity)
  end

  it "orders items by units sold at this branch, best first" do
    sale(burger, quantity: 2)
    sale(fries, quantity: 5)
    sale(burger, quantity: 1)
    sale(cola, quantity: 1)

    expect(described_class.call(location: branch)).to eq([fries.id, burger.id, cola.id])
  end

  it "counts only completed orders" do
    sale(burger, quantity: 1)
    %w[draft submitted in_progress ready cancelled].each { |status| sale(fries, quantity: 9, status: status) }

    expect(described_class.call(location: branch)).to eq([burger.id])
  end

  it "ignores other branches and sales older than 14 days" do
    sale(burger, quantity: 1)
    sale(fries, quantity: 9, location: other_branch)
    sale(cola, quantity: 9, placed_at: 15.days.ago)

    expect(described_class.call(location: branch)).to eq([burger.id])
  end

  it "respects the limit" do
    sale(burger, quantity: 3)
    sale(fries, quantity: 2)
    sale(cola, quantity: 1)

    expect(described_class.call(location: branch, limit: 2)).to eq([burger.id, fries.id])
  end

  it "returns nothing without a branch" do
    expect(described_class.call(location: nil)).to eq([])
  end
end
