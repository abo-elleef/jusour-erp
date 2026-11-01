# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::CategoryAnalysisService, "change against the previous period" do
  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company, wages_account_code: 3201) }
  let!(:cash) do
    Treasury.create!(name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 10_000_000, opening_balance_cents: 10_000_000, company: company)
  end
  let!(:rent) { ExpenseCategory.create!(name: "Rent", category_type: "other", position: 1, company: company) }
  let!(:repairs) { ExpenseCategory.create!(name: "Repairs", category_type: "other", position: 2, company: company) }
  let!(:fuel) { ExpenseCategory.create!(name: "Fuel", category_type: "other", position: 3, company: company) }

  def spend(cents, category, on)
    Expense.create!(expense_category: category, amount_cents: cents, expense_date: on,
      description: "x", recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company)
  end

  def analyse(from, to) = described_class.new(start_date: from, end_date: to, kind: "expense").call
  def row(result, category) = result.rows.find { |r| r.category == category }

  it "compares a calendar month with the month before it" do
    spend(10_000, rent, Date.new(2026, 8, 5))
    spend(12_000, rent, Date.new(2026, 9, 5))
    spend(1_000, repairs, Date.new(2026, 8, 9))
    spend(4_000, repairs, Date.new(2026, 9, 9))
    spend(500, fuel, Date.new(2026, 9, 2))

    result = analyse(Date.new(2026, 9, 1), Date.new(2026, 9, 30))

    expect([result.previous_start, result.previous_end]).to eq([Date.new(2026, 8, 1), Date.new(2026, 8, 31)])
    expect([row(result, rent).previous_cents, row(result, rent).change_cents, row(result, rent).change_pct]).to eq([10_000, 2_000, 20.0])
    expect(row(result, fuel).change_pct).to be_nil # nothing the month before: new, not +∞%
    expect(result.biggest_increases.map(&:category)).to eq([repairs, rent, fuel])
  end

  it "compares a quarter with the quarter before it" do
    result = analyse(Date.new(2026, 7, 1), Date.new(2026, 9, 30))

    expect([result.previous_start, result.previous_end]).to eq([Date.new(2026, 4, 1), Date.new(2026, 6, 30)])
  end

  it "compares any other range with the same number of days just before it" do
    spend(700, rent, Date.new(2026, 9, 5))
    spend(900, rent, Date.new(2026, 9, 15))

    result = analyse(Date.new(2026, 9, 10), Date.new(2026, 9, 19))

    expect([result.previous_start, result.previous_end]).to eq([Date.new(2026, 8, 31), Date.new(2026, 9, 9)])
    expect(row(result, rent).previous_cents).to eq(700)
  end
end
