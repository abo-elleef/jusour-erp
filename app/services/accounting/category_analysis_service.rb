# frozen_string_literal: true

module Accounting
  # Expense and income broken down by category over a date range: what each
  # category cost or earned, how much of the total it accounts for, and how it
  # moved over time.
  #
  # Reversed entries are excluded throughout. A reversal cancels the record, so
  # counting it would overstate both the totals and the entry counts.
  class CategoryAnalysisService
    GRANULARITIES = %w[day week month].freeze
    KINDS = %w[both expense income].freeze

    Row = Struct.new(:category, :kind, :total_cents, :entry_count, :amounts,
                     :share_pct, keyword_init: true) do
      def average_cents
        entry_count.zero? ? 0 : (total_cents.to_f / entry_count).round
      end
    end

    Result = Struct.new(:rows, :periods, :period_labels, :granularity, :series,
                        :expense_cents, :income_cents, :entry_count,
                        :categories, keyword_init: true) do
      def net_cents
        income_cents - expense_cents
      end
    end

    def initialize(start_date:, end_date:, kind: nil, category_ids: nil, granularity: nil)
      @start_date = start_date
      @end_date = end_date
      @kind = KINDS.include?(kind.to_s) ? kind.to_s : "both"
      @category_ids = Array(category_ids).compact_blank.presence
      @granularity = GRANULARITIES.include?(granularity.to_s) ? granularity.to_s : default_granularity
    end

    def call
      rows = []
      rows.concat(build_rows(:expense)) if @kind != "income"
      rows.concat(build_rows(:income)) if @kind != "expense"

      expense_cents = rows.select { |row| row.kind == :expense }.sum(&:total_cents)
      income_cents = rows.select { |row| row.kind == :income }.sum(&:total_cents)
      # Share is of the side a category belongs to: a rent line is 30% of spend,
      # not 30% of "everything that moved", which would mean nothing.
      assign_shares!(rows, expense_cents, income_cents)

      Result.new(
        rows: rows.sort_by { |row| [row.kind == :expense ? 0 : 1, -row.total_cents] },
        periods: periods,
        period_labels: periods.map { |period| period_label(period) },
        granularity: @granularity,
        series: build_series(rows),
        expense_cents: expense_cents,
        income_cents: income_cents,
        entry_count: rows.sum(&:entry_count),
        categories: available_categories
      )
    end

    private

    def build_rows(kind)
      date_column = kind == :expense ? :expense_date : :income_date
      category_key = kind == :expense ? :expense_category_id : :income_category_id

      scope = (kind == :expense ? Expense : Income)
        .where(reversed_at: nil, date_column => @start_date..@end_date)
      scope = scope.where(category_key => @category_ids) if @category_ids

      # Aggregated in the database: a year of entries is far too many to load.
      totals = scope.group(category_key, date_column).pluck(
        category_key, date_column, Arel.sql("SUM(amount_cents)"), Arel.sql("COUNT(*)")
      )
      return [] if totals.empty?

      categories = (kind == :expense ? ExpenseCategory : IncomeCategory)
        .where(id: totals.map(&:first).uniq).index_by(&:id)

      grouped = Hash.new { |hash, key| hash[key] = { amounts: Hash.new(0), count: 0 } }
      totals.each do |category_id, date, sum_cents, count|
        bucket = grouped[category_id]
        bucket[:amounts][period_for(date)] += sum_cents.to_i
        bucket[:count] += count.to_i
      end

      grouped.filter_map do |category_id, bucket|
        category = categories[category_id]
        next if category.nil?

        Row.new(
          category: category,
          kind: kind,
          total_cents: bucket[:amounts].values.sum,
          entry_count: bucket[:count],
          amounts: bucket[:amounts],
          share_pct: 0
        )
      end
    end

    def assign_shares!(rows, expense_cents, income_cents)
      rows.each do |row|
        side_total = row.kind == :expense ? expense_cents : income_cents
        row.share_pct = side_total.zero? ? 0.0 : ((row.total_cents * 100.0) / side_total).round(1)
      end
    end

    # Chart values are in currency units, not cents — the axis is read as money.
    def build_series(rows)
      rows
        .sort_by { |row| -row.total_cents }
        .map do |row|
          {
            row: row,
            key: "#{row.kind}-#{row.category.id}",
            total_cents: row.total_cents,
            data: periods.index_with { |period| (row.amounts[period] || 0) / 100.0 }
          }
        end
    end

    # Every category that could be filtered on, whether or not it has entries in
    # the current range — otherwise the filter can only ever narrow.
    def available_categories
      {
        expense: @kind == "income" ? [] : ExpenseCategory.ordered.to_a,
        income: @kind == "expense" ? [] : IncomeCategory.ordered.to_a
      }
    end

    def periods
      @periods ||= begin
        list = []
        cursor = period_for(@start_date)
        last = period_for(@end_date)
        while cursor <= last
          list << cursor
          cursor = advance(cursor)
        end
        list
      end
    end

    def period_for(date)
      case @granularity
      when "week" then date.beginning_of_week
      when "month" then date.beginning_of_month
      else date
      end
    end

    def advance(period)
      case @granularity
      when "week" then period + 1.week
      when "month" then period + 1.month
      else period + 1.day
      end
    end

    def period_label(period)
      case @granularity
      when "month" then I18n.l(period, format: "%B %Y")
      when "week" then week_label(period)
      else I18n.l(period, format: "%a %d %b")
      end
    end

    # Weeks run Saturday to Friday, set app-wide by config.beginning_of_week so
    # payroll, the overtime check and every weekly report agree. The label spells
    # out both ends: a lone start date leaves the reader guessing where it stops.
    def week_label(period)
      finish = period.end_of_week
      start_format = period.month == finish.month ? "%d" : "%d %b"
      "#{I18n.l(period, format: start_format)} – #{I18n.l(finish, format: "%d %b")}"
    end

    # A day-by-day line over a year is unreadable; pick a bucket that fits the
    # range unless the accountant asked for a specific one.
    def default_granularity
      days = (@end_date - @start_date).to_i
      return "day" if days <= 45
      return "week" if days <= 400

      "month"
    end
  end
end
