# frozen_string_literal: true

module Accounting
  # The profit figure shown on the accounting dashboard, on the sales report, and
  # pushed to QuickBooks/Xero.
  #
  # The financial numbers come from the ledger (via ChartOfAccountsService), so they
  # match the Profit & Loss statement to the cent and count every way the company
  # earns — POS takings recognised at day close, credit sales invoiced to customers,
  # and manual income alike. It used to read `Order.completed` directly, which meant
  # distribution companies saw no revenue at all and the two reports disagreed.
  #
  # The `revenue` breakdown keeps its order-derived detail (discounts, refunds, tips):
  # that is POS operating detail the ledger does not carry, and it is simply zero for
  # a company that does not use the POS.
  class PnlService
    def initialize(start_date, end_date)
      @start_date = start_date
      @end_date = end_date
      @range = BusinessDay.range_between(start_date, end_date)
      @date_range = start_date..end_date
    end

    def call
      {
        revenue: revenue_breakdown,
        expenses: expense_breakdown,
        gross_profit_cents: net_revenue_cents - cogs_cents,
        net_profit_cents: net_revenue_cents - total_expenses_cents
      }
    end

    private

    def coa
      @coa ||= ChartOfAccountsService.new(start_date: @start_date, end_date: @end_date)
    end

    # Everything credited to a revenue account in the period, net of credit notes.
    def net_revenue_cents
      @net_revenue_cents ||= coa.total_revenue_cents
    end

    def completed_orders
      @completed_orders ||= Order.completed.where(created_at: @range)
    end

    def refunds_cents
      @refunds_cents ||= RevenueCalculator.refunds_cents(completed_orders.pluck(:id))
    end

    # `net_sales_cents` is the ledger figure — it is what the dashboard, the P&L
    # statement and the accounting-software sync all quote. The rest is POS colour.
    def revenue_breakdown
      {
        gross_sales_cents: completed_orders.sum(:subtotal_cents).to_i,
        discounts_cents: completed_orders.sum(:discount_cents).to_i,
        refunds_cents: refunds_cents,
        net_sales_cents: net_revenue_cents,
        tax_collected_cents: completed_orders.sum(:tax_cents).to_i,
        tips_cents: completed_orders.sum(:tip_cents).to_i
      }
    end

    def expense_breakdown
      coa.expense_lines.map do |line|
        { category: line.name, category_type: line.subtype, total_cents: line.balance_cents }
      end
    end

    # Cost of goods is expensed when goods are bought, not when they are sold —
    # the app keeps periodic inventory — so this is the purchases account.
    def cogs_cents
      @cogs_cents ||= coa.expense_lines
        .select { |line| line.code == PURCHASES_CODE }
        .sum(&:balance_cents)
    end

    def total_expenses_cents
      @total_expenses_cents ||= coa.total_expenses_cents
    end

    PURCHASES_CODE = 5100
  end
end
