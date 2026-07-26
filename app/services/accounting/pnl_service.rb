# frozen_string_literal: true

module Accounting
  class PnlService
    def initialize(start_date, end_date)
      @range = BusinessDay.range_between(start_date, end_date)
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
      @completed_orders ||= Order.completed.where(created_at: @range)
    end

    def gross_revenue_cents
      RevenueCalculator.order_net_sales(completed_orders) - refunds_cents
    end

    def refunds_cents
      @refunds_cents ||= RevenueCalculator.refunds_cents(completed_orders.pluck(:id))
    end

    def revenue_breakdown
      gross = completed_orders.sum(:subtotal_cents).to_i
      discounts = completed_orders.sum(:discount_cents).to_i
      {
        gross_sales_cents: gross,
        discounts_cents: discounts,
        refunds_cents: refunds_cents,
        net_sales_cents: gross - discounts - refunds_cents,
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
