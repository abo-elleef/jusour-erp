# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounting category analysis report", type: :request do
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

  def spend(cents, category: rent, on: 3.days.ago.to_date)
    Expense.create!(expense_category: category, amount_cents: cents, expense_date: on,
      description: "x", recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company)
  end

  def earn(cents, category: catering, on: 3.days.ago.to_date)
    Income.create!(income_category: category, amount_cents: cents, income_date: on,
      description: "x", recurrence: "one_time", user: owner, treasury: cash,
      is_auto_generated: false, company: company)
  end

  def analysis(**params)
    get admin_accounting_category_analysis_index_path(
      { start_date: 30.days.ago.to_date, end_date: Date.current }.merge(params)
    )
    @request.env["action_controller.instance"].instance_variable_get(:@analysis)
  end

  def row_for(result, name)
    result.rows.find { |row| row.category.name == name }
  end

  before { sign_in owner }

  describe "what it counts" do
    it "totals each category and counts its entries" do
      spend(20_000)
      spend(10_000)
      spend(5_000, category: supplies)
      earn(50_000)

      result = analysis

      expect(row_for(result, "Rent").total_cents).to eq(30_000)
      expect(row_for(result, "Rent").entry_count).to eq(2)
      expect(row_for(result, "Supplies").total_cents).to eq(5_000)
      expect(row_for(result, "Catering").total_cents).to eq(50_000)
      expect(result.expense_cents).to eq(35_000)
      expect(result.income_cents).to eq(50_000)
      expect(result.net_cents).to eq(15_000)
      expect(result.entry_count).to eq(4)
    end

    it "never counts a deleted entry" do
      spend(20_000)
      gone = spend(80_000)
      delete admin_accounting_expense_path(gone)

      result = analysis

      expect(row_for(result, "Rent").total_cents).to eq(20_000)
      expect(row_for(result, "Rent").entry_count).to eq(1)
      expect(result.expense_cents).to eq(20_000)
    end

    it "excludes entries outside the date range" do
      spend(20_000, on: 3.days.ago.to_date)
      spend(90_000, on: 90.days.ago.to_date)

      expect(analysis.expense_cents).to eq(20_000)
    end

    it "reports an average per entry" do
      spend(10_000)
      spend(20_000)

      expect(row_for(analysis, "Rent").average_cents).to eq(15_000)
    end
  end

  describe "share" do
    it "measures a category against its own side, not the combined total" do
      spend(75_000)
      spend(25_000, category: supplies)
      earn(400_000)

      result = analysis

      # Rent is 75% of spend — not 75/500 of everything that moved.
      expect(row_for(result, "Rent").share_pct).to eq(75.0)
      expect(row_for(result, "Supplies").share_pct).to eq(25.0)
      expect(row_for(result, "Catering").share_pct).to eq(100.0)
    end

    it "does not divide by zero when a side is empty" do
      earn(50_000)

      result = analysis(kind: "both")

      expect(result.expense_cents).to eq(0)
      expect(row_for(result, "Catering").share_pct).to eq(100.0)
    end
  end

  describe "filters" do
    it "narrows to expenses or incomes only" do
      spend(20_000)
      earn(50_000)

      expect(analysis(kind: "expense").rows.map { |r| r.category.name }).to eq(["Rent"])
      expect(analysis(kind: "income").rows.map { |r| r.category.name }).to eq(["Catering"])
      expect(analysis(kind: "both").rows.size).to eq(2)
    end

    it "narrows to chosen categories" do
      spend(20_000)
      spend(5_000, category: supplies)
      earn(50_000)

      result = analysis(category_ids: [supplies.id])

      expect(result.rows.map { |r| r.category.name }).to eq(["Supplies"])
      expect(result.expense_cents).to eq(5_000)
    end

    it "offers every category for filtering, not just the ones with entries" do
      spend(20_000)

      result = analysis

      expect(result.categories[:expense].map(&:name)).to include("Rent", "Supplies")
      expect(result.categories[:income].map(&:name)).to include("Catering")
    end

    it "lists filter categories in configured position order, not alphabetically" do
      # Positions deliberately invert the alphabet, so name ordering would fail.
      ExpenseCategory.create!(name: "Zebra", category_type: "other", position: 5, company: company)
      ExpenseCategory.create!(name: "Alpha", category_type: "other", position: 90, company: company)

      names = analysis.categories[:expense].map(&:name)

      expect(names.index("Zebra")).to be < names.index("Alpha")
    end
  end

  describe "periods" do
    it "buckets by day and keeps empty periods" do
      spend(10_000, on: Date.current)
      spend(3_000, on: 2.days.ago.to_date)

      result = analysis(start_date: 4.days.ago.to_date, end_date: Date.current, granularity: "day")

      row = row_for(result, "Rent")
      expect(result.periods.size).to eq(5)
      expect(row.amounts[Date.current]).to eq(10_000)
      expect(row.amounts[2.days.ago.to_date]).to eq(3_000)
      expect(row.amounts[1.day.ago.to_date]).to eq(0)
      expect(result.series.first[:data].size).to eq(5)
    end

    it "rolls days into one bucket when grouping by month" do
      spend(10_000, on: Date.current.beginning_of_month)
      spend(5_000, on: Date.current.beginning_of_month + 1)

      result = analysis(start_date: Date.current.beginning_of_month, end_date: Date.current, granularity: "month")

      expect(row_for(result, "Rent").amounts.size).to eq(1)
      expect(row_for(result, "Rent").amounts[Date.current.beginning_of_month]).to eq(15_000)
    end

    it "runs weeks Saturday to Friday and labels both ends" do
      spend(10_000)

      result = analysis(start_date: 120.days.ago.to_date, end_date: Date.current, granularity: "week")
      first = result.periods.first

      expect(first.strftime("%A")).to eq("Saturday")
      expect(first.end_of_week.strftime("%A")).to eq("Friday")
      expect(result.period_labels.first)
        .to eq("#{I18n.l(first, format: first.month == first.end_of_week.month ? "%d" : "%d %b")} – #{I18n.l(first.end_of_week, format: "%d %b")}")
      # Consecutive buckets are exactly seven days apart, with no gap or overlap.
      expect(result.periods.each_cons(2).all? { |a, b| (b - a).to_i == 7 }).to be true
    end

    it "names the weekday on daily buckets only" do
      spend(10_000)

      day = analysis(start_date: 10.days.ago.to_date, end_date: Date.current, granularity: "day")
      month = analysis(start_date: 400.days.ago.to_date, end_date: Date.current, granularity: "month")

      expect(day.period_labels.first).to match(/\A#{I18n.l(day.periods.first, format: "%a")} /)
      expect(month.period_labels.first).to eq(I18n.l(month.periods.first, format: "%B %Y"))
    end
  end

  describe "the page" do
    it "renders the chart, picker and table wired together" do
      spend(20_000)
      earn(50_000)

      get admin_accounting_category_analysis_index_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include("category-analysis-chart")
      expect(response.body).to include('data-chart-series-storage-key-value="saqr:category-analysis:series"')
      expect(response.body).to include(%(data-series-key="expense-#{rent.id}"))
      expect(response.body).to include(%(data-series-key="income-#{catering.id}"))
      expect(response.body).to include(I18n.t("accounting.category_analysis.table_heading"))
      expect(response.body).to include(I18n.t("accounting.category_analysis.nothing_selected"))
    end

    it "gives every series a colour, past chartkick's twenty" do
      25.times do |n|
        category = ExpenseCategory.create!(name: "Cat #{format('%02d', n)}", category_type: "other",
          position: n + 10, company: company)
        spend(1_000 * (n + 1), category: category)
      end

      get admin_accounting_category_analysis_index_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      colors = response.body[/&quot;colors&quot;:\[(.*?)\]/, 1] || response.body[/"colors":\[(.*?)\]/, 1]
      entries = colors.to_s.scan(/#[0-9A-F]{6}/)
      expect(entries.size).to eq(25)
      expect(entries.uniq.size).to eq(25)
    end

    it "says so when nothing was recorded" do
      get admin_accounting_category_analysis_index_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include(I18n.t("accounting.category_analysis.empty"))
    end

    it "is reachable from the accounting reports nav" do
      get admin_accounting_usage_reports_path

      expect(response.body).to include(admin_accounting_category_analysis_index_path)
      expect(response.body).to include(I18n.t("accounting.nav.category_analysis"))
    end

    it "exports the rows as CSV" do
      spend(20_000)
      earn(50_000)

      get admin_accounting_category_analysis_index_path(format: :csv, start_date: 30.days.ago.to_date,
        end_date: Date.current, granularity: "month")

      expect(response.body).to include("Type,Category,Entries,Total,Share %,Average")
      expect(response.body).to include("Rent")
      expect(response.body).to include("Catering")
    end
    it "splits the category filter into an expense column and an income column" do
      spend(20_000)

      get admin_accounting_category_analysis_index_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      expect(response.body).to include("md:grid-cols-2")
      # The type is a column heading now, not a badge on every row — that
      # repetition was what made the filter unreadable.
      rows = response.body.scan(/<label[^>]*>\s*<input[^>]*name="category_ids\[\]".*?<\/label>/m)
      expect(rows).to be_present
      expect(rows.count { |row| row.include?(I18n.t("accounting.category_analysis.kind.expense")) }).to eq(0)
    end

    it "collapses to a single column when only one kind is in play" do
      spend(20_000)

      get admin_accounting_category_analysis_index_path(start_date: 30.days.ago.to_date,
        end_date: Date.current, kind: "expense")

      expect(response.body).not_to include("md:grid-cols-2")
      expect(response.body).to include(%(name="category_ids[]"))
    end
  end

  describe "drilling into a number" do
    it "links a category total to its own ledger, filtered and dated" do
      spend(20_000)
      earn(50_000)

      get admin_accounting_category_analysis_index_path(start_date: 30.days.ago.to_date, end_date: Date.current)

      # Expense rows go to expenses, income rows to incomes — each carrying its
      # category, the report's dates, and the flag that keeps those dates out of
      # the shared session range.
      expect(response.body).to match(%r{/admin/accounting/expenses\?[^"]*category_id=#{rent.id}})
      expect(response.body).to match(%r{/admin/accounting/incomes\?[^"]*category_id=#{catering.id}})
      expect(response.body).to match(%r{/admin/accounting/expenses\?[^"]*transient_range=1})
      expect(response.body).to match(%r{/admin/accounting/expenses\?[^"]*end_date=#{Date.current}})
    end

    it "dates a period cell to that bucket, clamped to the report range" do
      # Report starts mid-week, so the first weekly bucket begins before it.
      start_date = Date.new(2026, 6, 3)
      end_date = Date.new(2026, 6, 20)
      spend(20_000, on: Date.new(2026, 6, 4))

      result = analysis(start_date: start_date, end_date: end_date, granularity: "week")
      first_period = result.periods.first
      from, to = result.period_bounds[first_period]

      expect(first_period).to be < start_date
      # Clamped: a drill-down must not list entries outside the analysed range.
      expect(from).to eq(start_date)
      expect(to).to eq(first_period.end_of_week)
      expect(result.period_bounds[result.periods.last].last).to eq(end_date)
    end

    it "does not offer a link on a zero cell" do
      spend(20_000, on: Date.current)

      get admin_accounting_category_analysis_index_path(start_date: 4.days.ago.to_date,
        end_date: Date.current, granularity: "day")

      # One dash per empty day for the single category.
      expect(response.body.scan(/>\s*—\s*</).size).to be >= 4
    end

    it "keeps a drill-down range out of the shared session range" do
      spend(20_000)

      # Establish a working range on the report.
      get admin_accounting_category_analysis_index_path(start_date: "2026-06-01", end_date: "2026-09-06")
      expect(session[:admin_start_date]).to eq("2026-06-01")

      # Drill into one narrow bucket.
      get admin_accounting_expenses_path(category_id: rent.id, start_date: "2026-08-29",
        end_date: "2026-09-04", transient_range: 1)
      expect(response).to have_http_status(:ok)

      # The working range survived: another report still opens where it was.
      expect(session[:admin_start_date]).to eq("2026-06-01")
      expect(session[:admin_end_date]).to eq("2026-09-06")
    end

    it "still persists a range the user actually chose" do
      get admin_accounting_expenses_path(start_date: "2026-07-01", end_date: "2026-07-31")

      expect(session[:admin_start_date]).to eq("2026-07-01")
      expect(session[:admin_end_date]).to eq("2026-07-31")
    end
  end
end
