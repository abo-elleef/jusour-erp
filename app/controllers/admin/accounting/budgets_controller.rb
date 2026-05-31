# frozen_string_literal: true

module Admin
  module Accounting
    class BudgetsController < BaseController
      def index
        @year = (params[:year] || Date.current.year).to_i
        @categories = ExpenseCategory.where(system_managed: false).ordered
        @months = (1..12).to_a

        @budgets = Budget.where(year: @year).includes(:expense_category).index_by do |b|
          [b.expense_category_id, b.month]
        end

        @actuals = Hash.new(0)
        Expense.where(expense_date: Date.new(@year, 1, 1)..Date.new(@year, 12, 31))
          .pluck(:expense_category_id, :expense_date, :amount_cents)
          .each do |cat_id, date, cents|
            @actuals[[cat_id, date.month]] += cents
          end
      end

      def update
        authorize :accounting, :update?
        category = ExpenseCategory.find(params[:expense_category_id])
        budget = Budget.find_or_initialize_by(
          expense_category: category,
          year: params[:year].to_i,
          month: params[:month].to_i
        )
        budget.amount_cents = (params[:amount_dollars].to_f * 100).round
        budget.save!
        redirect_to admin_accounting_budgets_path(year: params[:year]), notice: t("flash.accounting.budget_saved")
      end
    end
  end
end
