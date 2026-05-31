# frozen_string_literal: true

module Accounting
  class PnlService
    def initialize(start_date, end_date)
      @start = start_date.beginning_of_day
      @end = end_date.end_of_day
      @date_range = start_date..end_date
    end

    def call
      {
        revenue: revenue_breakdown,
        expenses: expense_breakdown,
        gross_profit_cents: gross_revenue_cents - cogs_cents,
        net_profit_cents: gross_revenue_cents - total_expenses_cents
      }
    end

    private

    def completed_orders
      @completed_orders ||= Order.completed.where(created_at: @start..@end)
    end

    def gross_revenue_cents
      completed_orders.sum(:subtotal_cents).to_i - completed_orders.sum(:discount_cents).to_i
    end

    def revenue_breakdown
      {
        gross_sales_cents: completed_orders.sum(:subtotal_cents).to_i,
        discounts_cents: completed_orders.sum(:discount_cents).to_i,
        refunds_cents: Payment.where(order: completed_orders, status: %w[refunded partially_refunded])
                              .sum(:refunded_amount_cents).to_i,
        net_sales_cents: gross_revenue_cents,
        tax_collected_cents: completed_orders.sum(:tax_cents).to_i,
        tips_cents: completed_orders.sum(:tip_cents).to_i
      }
    end

    def expense_breakdown
      ExpenseCategory.ordered.map do |cat|
        total = Expense.where(expense_category: cat).on_date_range(@date_range.first, @date_range.last).sum(:amount_cents)
        { category: cat.name, category_type: cat.category_type, total_cents: total.to_i }
      end
    end

    def cogs_cents
      Expense.joins(:expense_category)
             .where(expense_categories: { name: "COGS" })
             .on_date_range(@date_range.first, @date_range.last)
             .sum(:amount_cents).to_i
    end

    def total_expenses_cents
      Expense.on_date_range(@date_range.first, @date_range.last).sum(:amount_cents).to_i
    end
  end
end
