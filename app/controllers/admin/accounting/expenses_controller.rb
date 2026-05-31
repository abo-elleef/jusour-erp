# frozen_string_literal: true

module Admin
  module Accounting
    class ExpensesController < BaseController
      before_action :set_expense, only: %i[edit update destroy]

      def index
        parse_date_range
        @q = Expense.ransack(params[:q])
        scope = @q.result.includes(:expense_category, :user)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(is_auto_generated: false) if params[:manual_only] == "1"
        scope = scope.where(expense_category_id: params[:category_id]) if params[:category_id].present?

        @expenses = scope.order(expense_date: :desc, created_at: :desc).limit(200)
        @totals_by_category = Expense.joins(:expense_category)
          .on_date_range(@start_date, @end_date)
          .group("expense_categories.name")
          .sum(:amount_cents)
        @categories = ExpenseCategory.ordered
      end

      def new
        @expense = Expense.new(expense_date: Date.current, user: current_user)
        authorize @expense
        @categories = ExpenseCategory.manual.ordered
      end

      def create
        @expense = Expense.new(expense_params.merge(user: current_user, is_auto_generated: false))
        authorize @expense

        if @expense.save
          redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_recorded")
        else
          @categories = ExpenseCategory.manual.ordered
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @expense
        @categories = ExpenseCategory.manual.ordered
      end

      def update
        authorize @expense
        if @expense.update(expense_params)
          redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_updated")
        else
          @categories = ExpenseCategory.manual.ordered
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @expense
        AuditLogEntry.record!(action: "expense.delete", record: @expense, user: current_user)
        @expense.destroy!
        redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_removed")
      end

      private

      def set_expense
        @expense = Expense.find(params[:id])
      end

      def expense_params
        params.require(:expense).permit(
          :expense_category_id, :description, :amount_cents, :expense_date,
          :recurrence, :reference_number, :receipt_image
        )
      end
    end
  end
end
