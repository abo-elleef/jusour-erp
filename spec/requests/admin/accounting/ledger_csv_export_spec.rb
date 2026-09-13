# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Expense and income CSV export", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:cash) do
    Treasury.create!(name: "Cash Drawer", treasury_type: "cash_drawer",
      balance_cents: 10_000_000, opening_balance_cents: 10_000_000, company: company)
  end
  let!(:rent) { ExpenseCategory.create!(name: "Rent", category_type: "other", position: 1, company: company) }
  let!(:supplies) { ExpenseCategory.create!(name: "Supplies", category_type: "other", position: 2, company: company) }
  let!(:catering) { IncomeCategory.create!(name: "Catering", category_type: "other", position: 1, company: company) }

  def spend(cents, category: rent, on: Date.current, description: "x")
    Expense.create!(expense_category: category, amount_cents: cents, expense_date: on,
      description: description, recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company)
  end

  def earn(cents, on: Date.current, description: "y")
    Income.create!(income_category: catering, amount_cents: cents, income_date: on,
      description: description, recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company)
  end

  def rows(body)
    CSV.parse(body).drop(1)
  end

  before { sign_in owner }

  it "exports expenses for the range on screen" do
    spend(20_000, description: "In range")
    spend(90_000, on: 90.days.ago.to_date, description: "Out of range")

    get admin_accounting_expenses_path(format: :csv, start_date: 30.days.ago.to_date, end_date: Date.current)

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("In range")
    expect(response.body).not_to include("Out of range")
  end

  it "honours a category filter arriving from a report drill-down" do
    spend(20_000, category: rent, description: "Rent line")
    spend(5_000, category: supplies, description: "Supplies line")

    get admin_accounting_expenses_path(format: :csv, category_id: supplies.id,
      start_date: 30.days.ago.to_date, end_date: Date.current, transient_range: 1)

    expect(response.body).to include("Supplies line")
    expect(response.body).not_to include("Rent line")
  end

  it "exports every matching row, not just the first page" do
    60.times { |n| spend(1_000, description: "Row #{n}") }

    get admin_accounting_expenses_path(format: :csv, start_date: 30.days.ago.to_date, end_date: Date.current)

    # The HTML page paginates at 50; the export must not inherit that.
    expect(rows(response.body).size).to eq(60)
    expect(response.body).to include("Row 59")
  end

  # There is no longer a state the totals leave out: an expense that should not
  # stand is deleted, so the export is every row and every row counts.
  it "exports only rows that still exist" do
    spend(20_000, description: "Still counted")
    gone = spend(80_000, description: "Cancelled")

    delete admin_accounting_expense_path(gone)
    get admin_accounting_expenses_path(format: :csv, start_date: 30.days.ago.to_date, end_date: Date.current)

    parsed = rows(response.body)
    expect(parsed.find { |row| row.include?("Still counted") }).to be_present
    expect(parsed.find { |row| row.include?("Cancelled") }).to be_nil
  end

  it "exports incomes the same way" do
    earn(50_000, description: "Party booking")

    get admin_accounting_incomes_path(format: :csv, start_date: 30.days.ago.to_date, end_date: Date.current)

    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Party booking")
    expect(response.body).to include("Catering")
  end

  it "offers the export from the page, carrying the active filters" do
    spend(20_000, category: supplies)

    get admin_accounting_expenses_path(category_id: supplies.id,
      start_date: 30.days.ago.to_date, end_date: Date.current)

    expect(response.body).to include(I18n.t("actions.export_csv"))
    expect(response.body).to match(%r{/admin/accounting/expenses\.csv\?[^"]*category_id=#{supplies.id}})
  end
end
