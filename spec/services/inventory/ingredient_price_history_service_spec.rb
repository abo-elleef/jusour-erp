# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::IngredientPriceHistoryService, type: :service do
  let(:company) { Current.company }
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:ingredient) do
    Ingredient.create!(name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 250, quantity_on_hand: 0, company: company)
  end
  let(:supplier_a) { Supplier.create!(name: "Vendor A", company: company) }
  let(:supplier_b) { Supplier.create!(name: "Vendor B", company: company) }

  def record(price_cents, on:, supplier: supplier_a, created_at: nil)
    SupplierPriceHistory.create!(
      supplier: supplier, ingredient: ingredient, price_cents: price_cents,
      effective_date: on, created_at: created_at || Time.current
    )
  end

  def series(days: 7, as_of: Date.current)
    described_class.new(ingredient: ingredient, days: days, as_of: as_of).call
  end

  it "carries a price forward on days with no receipt" do
    record(1_000, on: Date.current - 5)

    result = series
    expect(result.values.uniq).to eq([10.0])
    # Starts the day the price was first known, not the first day of the window.
    expect(result.keys.first).to eq((Date.current - 5).to_s)
    expect(result.keys.last).to eq(Date.current.to_s)
  end

  it "seeds from the last price recorded before the window" do
    record(2_000, on: Date.current - 60)

    # Nothing inside the 7-day window, but the price was still in force.
    expect(series.values.uniq).to eq([20.0])
  end

  it "steps to the new price on the day it changes" do
    record(1_000, on: Date.current - 4)
    record(1_500, on: Date.current - 2)

    result = series
    expect(result[(Date.current - 3).to_s]).to eq(10.0)
    expect(result[(Date.current - 2).to_s]).to eq(15.0)
    expect(result[Date.current.to_s]).to eq(15.0)
  end

  it "tracks price from any vendor, not just one" do
    record(1_000, on: Date.current - 4, supplier: supplier_a)
    record(1_200, on: Date.current - 1, supplier: supplier_b)

    expect(series[Date.current.to_s]).to eq(12.0)
  end

  it "uses the last-recorded price when a day has several receipts" do
    day = Date.current - 3
    record(1_000, on: day, created_at: 3.hours.ago)
    record(1_800, on: day, created_at: 1.hour.ago)

    expect(series[day.to_s]).to eq(18.0)
  end

  it "omits days before any price was known rather than plotting zero" do
    record(1_000, on: Date.current - 1)

    result = series
    expect(result.keys).to eq([(Date.current - 1).to_s, Date.current.to_s])
    expect(result.values).to all(eq(10.0))
  end

  it "is empty when the ingredient was never priced" do
    expect(series).to eq({})
  end

  it "ignores prices recorded after the window ends" do
    record(1_000, on: Date.current - 10)
    record(9_900, on: Date.current)

    # A window that ends before today must not see today's price.
    expect(series(days: 3, as_of: Date.current - 5).values.uniq).to eq([10.0])
  end
end
