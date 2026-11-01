# frozen_string_literal: true

module Accounting
  # Month-by-month KPI scorecard for the owner. Every figure is taken from a
  # source another page already shows, so the scorecard never disagrees with it:
  #
  # - Sales, purchases and operating expenses: ChartOfAccountsService (the P&L).
  # - Cost of goods: opening stock + purchases − closing stock, the P&L's
  #   periodic method, from the hand-entered InventorySnapshots.
  # - Labour: LabourCostService (finalized payroll by payroll month).
  # - Receivables and payables: the customer AR / supplier AP treasuries,
  #   rebuilt to the month end from their transactions.
  #
  # A KPI whose inputs are missing is nil — shown as a dash — never a zero that
  # reads as a real result.
  class KpiScorecardService
    MONTHS = 6

    # Which way is good, for the month-on-month arrow.
    HIGHER_IS_BETTER = %i[revenue gross_margin net_margin dpo].freeze

    Month = Struct.new(:month, :revenue_cents, :cogs_cents, :operating_expenses_cents, :labour_percent,
                       :receivables_cents, :payables_cents, :purchases_cents, :closing_stock_cents,
                       :credit_sales, keyword_init: true) do
      def days = month.end_of_month.day

      def gross_margin = cogs_cents ? ratio(revenue_cents - cogs_cents, revenue_cents) : nil
      def net_margin = cogs_cents ? ratio(revenue_cents - cogs_cents - operating_expenses_cents, revenue_cents) : nil
      def food_cost = cogs_cents ? ratio(cogs_cents, revenue_cents) : nil
      def prime_cost = food_cost && labour_percent && food_cost + labour_percent

      # Days of sales still to collect. A business that does not sell on
      # credit collects at the till, so it is genuinely zero, not unknown.
      def dso
        return 0.0 unless credit_sales
        return nil unless revenue_cents.positive?

        receivables_cents * days / revenue_cents.to_f
      end

      def dpo = purchases_cents.positive? ? payables_cents * days / purchases_cents.to_f : nil
      def inventory_days = closing_stock_cents && cogs_cents.to_i.positive? ? closing_stock_cents * days / cogs_cents.to_f : nil
      def cash_cycle = dso && inventory_days && dpo && dso + inventory_days - dpo

      def revenue = revenue_cents

      private

      def ratio(part, whole) = whole.positive? ? part * 100.0 / whole : nil
    end

    def initialize(end_month:, months: MONTHS, today: Date.current)
      @last = end_month.beginning_of_month
      @first = @last << (months - 1)
      @today = today
    end

    # Oldest first; the view reverses for newest-first columns.
    def call
      labour = LabourCostService.new(start_date: @first, end_date: @last.end_of_month, today: @today).call
        .months.index_by(&:month)
      credit_sales = Current.company&.feature_enabled?(:ar_credit_sales) || false

      month_starts.map do |month|
        finish = month.end_of_month
        coa = ChartOfAccountsService.new(start_date: month, end_date: finish)
        opening, closing = stock_pair(month)

        Month.new(
          month: month,
          revenue_cents: coa.total_revenue_cents,
          purchases_cents: coa.purchases_cents,
          operating_expenses_cents: coa.total_operating_expenses_cents,
          cogs_cents: opening && closing && opening.value_cents + coa.purchases_cents - closing.value_cents,
          closing_stock_cents: closing&.value_cents,
          labour_percent: labour[month]&.percent,
          receivables_cents: balance_at(Treasury.customer_ar, finish),
          payables_cents: balance_at(Treasury.supplier_ap, finish),
          credit_sales: credit_sales
        )
      end
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

    # Opening = the latest count on or before the 1st. Closing = the latest
    # count on or before the month end — or, when that is still the opening
    # count, one taken on the 1st of next month (a count first thing on
    # 1 October is September's closing stock).
    def stock_pair(month)
      opening = snapshots.select { |s| s.snapshot_date <= month }.last
      closing = snapshots.select { |s| s.snapshot_date <= month.end_of_month }.last
      if closing.nil? || closing == opening
        closing = snapshots.find { |s| s.snapshot_date == month.next_month }
      end
      return [nil, nil] if opening.nil? || closing.nil? || closing == opening

      [opening, closing]
    end

    def snapshots
      @snapshots ||= InventorySnapshot.where(company: Current.company).order(:snapshot_date).to_a
    end

    def balance_at(treasuries, date)
      TreasuryTransaction.where(treasury_id: treasuries.select(:id), occurred_on: ..date).sum(:amount_cents).to_i
    end
  end
end
