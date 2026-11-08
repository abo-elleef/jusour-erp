# frozen_string_literal: true

require "rails_helper"

# At a table-service branch a table holds one open order at a time, from its first
# item until it is completed or cancelled. Everywhere else tables stay free-form.
RSpec.describe Order, "table service", type: :model do
  let(:company) { create(:company) }
  let(:user) { create(:user, company: company, role: "cashier") }
  let(:cafe) { create(:location, company: company, table_service: true, table_count: 10) }
  let(:restaurant) { create(:location, company: company, table_count: 10) }

  before { Current.company = company }

  def table_order(location:, table: "5", status: "draft", items: true)
    order = create(:order, user: user, company: company, location: location,
                           order_type: "table", table_number: table, status: status)
    create(:order_item, order: order) if items
    order
  end

  it "rejects a second order on a table that has an open order" do
    first = table_order(location: cafe)
    second = build(:order, user: user, company: company, location: cafe, order_type: "table", table_number: "5")

    expect(second).not_to be_valid
    expect(second.errors[:table_number].first).to include(first.order_number)
  end

  it "allows a different table" do
    table_order(location: cafe)
    expect(build(:order, user: user, company: company, location: cafe, order_type: "table", table_number: "6")).to be_valid
  end

  it "frees the table once the order is completed or cancelled" do
    table_order(location: cafe, status: "completed")
    table_order(location: cafe, status: "cancelled", table: "5")
    expect(build(:order, user: user, company: company, location: cafe, order_type: "table", table_number: "5")).to be_valid
  end

  it "keeps a paid-but-not-completed order's table busy" do
    table_order(location: cafe, status: "submitted")
    expect(build(:order, user: user, company: company, location: cafe, order_type: "table", table_number: "5")).not_to be_valid
  end

  it "does not let an empty cart hold a table" do
    table_order(location: cafe, items: false)
    expect(build(:order, user: user, company: company, location: cafe, order_type: "table", table_number: "5")).to be_valid
  end

  it "reports the conflict once the first item makes the cart real" do
    # Two registers pick the same free table while both carts are still empty.
    late = table_order(location: cafe, items: false)
    winner = table_order(location: cafe)

    expect(winner.table_conflict).to be_nil
    create(:order_item, order: late)
    expect(late.table_conflict).to eq(winner)
  end

  it "lets the holder of a table keep saving without tripping on itself" do
    order = table_order(location: cafe)
    expect(order.update(notes: "no sugar")).to be(true)
  end

  it "does not apply at a branch without table service" do
    table_order(location: restaurant)
    expect(build(:order, user: user, company: company, location: restaurant, order_type: "table", table_number: "5")).to be_valid
  end

  it "is scoped to its own branch" do
    other_cafe = create(:location, company: company, table_service: true, table_count: 10)
    table_order(location: cafe)
    expect(build(:order, user: user, company: company, location: other_cafe, order_type: "table", table_number: "5")).to be_valid
  end

  describe ".busy_tables" do
    it "maps table numbers to their open order, and is empty without table service" do
      order = table_order(location: cafe, table: "3")
      table_order(location: restaurant, table: "3")

      expect(Order.busy_tables(cafe)).to eq("3" => order)
      expect(Order.busy_tables(restaurant)).to eq({})
    end
  end

  describe Location do
    it "needs a table count when table service is on" do
      branch = build(:location, company: company, table_service: true, table_count: nil)
      expect(branch).not_to be_valid
    end
  end
end
