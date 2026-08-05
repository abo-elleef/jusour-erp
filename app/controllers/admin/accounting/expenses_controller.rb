# frozen_string_literal: true

module Admin
  module Accounting
    class ExpensesController < BaseController
      before_action :set_expense, only: %i[show edit update reverse]

      def show
        authorize @expense
        @je = JournalEntry.for_source(@expense).includes(:lines).first
      end

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)
        @q = Expense.ransack(params[:q])
        scope = @q.result.includes(:expense_category, :user, :treasury, :source_record)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(is_auto_generated: false) if params[:manual_only] == "1"
        scope = scope.where(expense_category_id: params[:category_id]) if params[:category_id].present?

        @total_count    = scope.count
        @reversed_count = scope.where.not(reversed_at: nil).count
        @active_count   = scope.where(reversed_at: nil).count
        @range_sums = [
          {
            label: t("accounting.expenses.stats_spent"),
            cents: scope.where(reversed_at: nil).unscope(:includes).sum(:amount_cents),
            tone: :danger
          }
        ]
        @pagy, @expenses = pagy(:offset, scope.order(expense_date: :desc, created_at: :desc), limit: 50)
        @active_category_id = params[:category_id].presence
        @totals_by_category = Expense.joins(:expense_category)
          .on_date_range(@start_date, @end_date)
          .where(reversed_at: nil)
          .group("expense_categories.id", "expense_categories.name")
          .sum(:amount_cents)
        @categories = ExpenseCategory.ordered
      end

      def new
        @expense = Expense.new(expense_date: Date.current, user: current_user, treasury: Treasury.default_treasury)
        authorize @expense
        @categories = ExpenseCategory.manual.ordered
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def create
        @expense = Expense.new(expense_params.merge(user: current_user, is_auto_generated: false))
        authorize @expense

        if @expense.save
          redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_recorded")
        else
          @categories = ExpenseCategory.manual.ordered
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @expense
        if @expense.reversed_at.present?
          return redirect_to admin_accounting_expenses_path,
                             alert: t("accounting.reversal.cannot_edit_reversed")
        end
        @categories = ExpenseCategory.manual.ordered
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def update
        authorize @expense
        if @expense.reversed_at.present?
          return redirect_to admin_accounting_expenses_path,
                             alert: t("accounting.reversal.cannot_edit_reversed")
        end
        if @expense.update(expense_params)
          redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_updated")
        else
          @categories = ExpenseCategory.manual.ordered
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :edit, status: :unprocessable_entity
        end
      end

      def reverse
        authorize @expense, :destroy?
        je = JournalEntry.for_source(@expense).first

        if je.nil?
          return redirect_to admin_accounting_expenses_path,
                             alert: t("accounting.reversal.no_journal_entry")
        end

        if @expense.reversed_at.present? || je.reversed?
          return redirect_to admin_accounting_expenses_path,
                             alert: t("accounting.reversal.already_reversed")
        end

        ActiveRecord::Base.transaction do
          reversal = ::Accounting::JournalEntryService.record_reversal!(
            original_je: je, user: current_user
          )
          sync_je_treasuries!(reversal)
          @expense.update_column(:reversed_at, Time.current)
          AuditLogEntry.record!(action: "expense.reverse", record: @expense, user: current_user)
        end

        redirect_to admin_accounting_expenses_path,
                    notice: t("accounting.reversal.expense_reversed")
      end

      private

      def set_expense
        @expense = Expense.find(params[:id])
      end

      def expense_params
        params.require(:expense).permit(
          :expense_category_id, :treasury_id, :description, :amount_pounds, :expense_date,
          :recurrence, :reference_number, :receipt_image
        )
      end
    end
  end
end
