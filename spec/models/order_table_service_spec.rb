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
    expect(second.errors[:table_number].first).to include(first.display_reference)
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

  it "keeps an unpaid, not completed order's table busy" do
    table_order(location: cafe, status: "submitted")
    expect(build(:order, user: user, company: company, location: cafe, order_type: "table", table_number: "5")).not_to be_valid
  end

  describe "freeing the table on payment" do
    def paid_table_order(location:, total: 5_000, paid: 5_000, status: "submitted")
      order = table_order(location: location, status: status)
      order.update_columns(total_cents: total)
      create(:payment, order: order, amount_cents: paid) if paid.positive?
      order
    end

    def new_order_on_table_5(location = cafe)
      build(:order, user: user, company: company, location: location, order_type: "table", table_number: "5")
    end

    it "is on by default for a new branch" do
      expect(Location.new.free_table_on_payment).to be(true)
    end

    it "frees the table once the order is fully paid, while the order stays open" do
      order = paid_table_order(location: cafe)

      expect(Order.busy_tables(cafe)).to eq({})
      expect(new_order_on_table_5).to be_valid
      expect(order.reload.status).to eq("submitted")
    end

    it "keeps the table busy while part of the order is still owed" do
      paid_table_order(location: cafe, paid: 2_000)
      expect(new_order_on_table_5).not_to be_valid
    end

    it "does not count a zero-total order as paid" do
      paid_table_order(location: cafe, total: 0, paid: 0)
      expect(new_order_on_table_5).not_to be_valid
    end

    it "frees the table for a fully paid draft too (paid before being placed)" do
      paid_table_order(location: cafe, status: "draft")
      expect(Order.busy_tables(cafe)).to eq({})
    end

    it "holds the table again when the order owes money again" do
      order = paid_table_order(location: cafe)
      order.update_columns(total_cents: 7_000)

      expect(Order.busy_tables(cafe)).to eq("5" => order)
    end

    it "keeps the table until completion where the branch turned it off" do
      cafe.update!(free_table_on_payment: false)
      order = paid_table_order(location: cafe)

      expect(Order.busy_tables(cafe)).to eq("5" => order)
      expect(new_order_on_table_5).not_to be_valid
    end

    it "lets a new order on a freed table save without tripping on the paid one" do
      paid_table_order(location: cafe)
      newer = table_order(location: cafe)

      expect(newer.table_conflict).to be_nil
      expect(Order.busy_tables(cafe)).to eq("5" => newer)
    end
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
