# frozen_string_literal: true

module Accounting
  # Labour cost as a share of sales, month by month, for the whole company.
  #
  # Cost is what staff earned for the month — PayrollSnapshot#net_pay_cents,
  # after bonuses and penalties — keyed by payroll month, so a month's pay sits
  # against that month's sales however late it was finalized. Revenue is the
  # P&L's: journal lines of type revenue, credit minus debit, by entry date.
  #
  # Company-wide on purpose: revenue mostly arrives as daily-closing incomes,
  # which carry no branch, so a per-branch share cannot be computed honestly.
  class LabourCostService
    Month = Struct.new(:month, :revenue_cents, :cost_cents, :headcount, :status, keyword_init: true) do
      # Only a complete month has a share: one finalized salary against a full
      # month of sales reads as 0%, which is wrong, not low.
      def percent = status == :complete && revenue_cents.positive? ? cost_cents * 100.0 / revenue_cents : nil
      def cost_per_head_cents = headcount.positive? ? cost_cents / headcount : nil
    end

    Result = Struct.new(:months, keyword_init: true) do
      # Totals take only complete months: one whose payroll is not finalized
      # would pull the share down, one with pay but no recorded sales (before
      # the journal went live) would push it up.
      def complete = months.select { |month| month.status == :complete }
      def revenue_cents = complete.sum(&:revenue_cents)
      def cost_cents = complete.sum(&:cost_cents)
      def percent = revenue_cents.positive? ? cost_cents * 100.0 / revenue_cents : nil
    end

    def initialize(start_date:, end_date:, today: Date.current)
      @first = start_date.beginning_of_month
      @last = end_date.beginning_of_month
      @today = today
    end

    def call
      revenue = revenue_by_month
      payroll = payroll_by_month
      months = month_starts.map do |month|
        cost, headcount = payroll.fetch(month, [0, 0])
        sales = revenue.fetch(month, 0)
        next if sales.zero? && headcount.zero? && month < @today.beginning_of_month

        Month.new(month: month, revenue_cents: sales, cost_cents: cost,
                  headcount: headcount, status: status_for(month, headcount, sales))
      end
      Result.new(months: months.compact)
    end

    private

    def month_starts
      months = []
      month = @first
      while month <= @last
        months << month
        month = month.next_month
      end
      months
    end

    # :current — the month is not over; :not_finalized — no payroll yet;
    # :partial — far fewer staff finalized than the period's usual headcount;
    # :no_revenue — pay but no sales on the books for the month.
    def status_for(month, headcount, sales)
      return :current if month >= @today.beginning_of_month
      return :not_finalized if headcount.zero?
      return :partial if headcount < usual_headcount / 2.0
      return :no_revenue if sales <= 0

      :complete
    end

    def usual_headcount
      @usual_headcount ||= begin
        counts = payroll_by_month.values.map(&:last).sort
        counts.empty? ? 0 : counts[counts.size / 2]
      end
    end

    def revenue_by_month
      JournalEntryLine.joins(:journal_entry)
        .where(account_type: "revenue", journal_entries: { date: @first..@last.end_of_month })
        .group(Arel.sql("date_trunc('month', journal_entries.date)::date"))
        .pluck(Arel.sql("date_trunc('month', journal_entries.date)::date AS month"),
               Arel.sql("SUM(journal_entry_lines.credit_cents - journal_entry_lines.debit_cents) AS revenue"))
        .to_h { |month, cents| [month, cents.to_i] }
    end

    def payroll_by_month
      @payroll_by_month ||= PayrollSnapshot.where(payroll_month: @first..@last)
        .group(:payroll_month)
        .pluck(:payroll_month, Arel.sql("SUM(net_pay_cents) AS cost"), Arel.sql("COUNT(*) AS headcount"))
        .to_h { |month, cost, headcount| [month, [cost.to_i, headcount.to_i]] }
    end
  end
end
