# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class ExpensesController < BaseController
      before_action :set_expense, only: %i[show edit update destroy]

      def show
        authorize @expense
        @je = JournalEntry.for_source(@expense).includes(:lines).first
        @audits = @expense.audits.includes(:user).reorder(version: :desc)
      end

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)
        @q = Expense.ransack(params[:q])
        scope = @q.result.includes(:expense_category, :user, :treasury, :source_record)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(is_auto_generated: false) if params[:manual_only] == "1"
        scope = scope.where(expense_category_id: params[:category_id]) if params[:category_id].present?
        @total_count = scope.count
        totals_scope = scope.unscope(:includes)
        @total_active_cents  = totals_scope.sum(:amount_cents)
        @system_cents        = totals_scope.where(is_auto_generated: true).sum(:amount_cents)
        @custom_cents        = totals_scope.where(is_auto_generated: false).sum(:amount_cents)

        # Ledger summary — from journal entry lines so it matches the P&L exactly
        @ledger_tab = params[:tab] == "ledger"
        @ledger_summary = build_ledger_summary(@start_date, @end_date)
        @range_sums = [
          {
            label: t("accounting.expenses.stats_spent"),
            cents: @total_active_cents,
            tone: :danger
          }
        ]
        ordered = scope.order(expense_date: :desc, created_at: :desc)

        # CSV exports the whole filtered set, not the page on screen — an export
        # that silently stopped at 50 rows would be worse than none.
        if request.format.csv?
          return send_data expenses_csv(ordered),
            filename: "expenses-#{@start_date}-#{@end_date}.csv",
            type: "text/csv; charset=utf-8"
        end

        @pagy, @expenses = pagy(:offset, ordered, limit: 50)
        @active_category_id = params[:category_id].presence
        @totals_by_category = Expense.joins(:expense_category)
          .on_date_range(@start_date, @end_date)
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
        @categories = ExpenseCategory.manual.ordered
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def update
        authorize @expense
        if @expense.update(expense_params)
          redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_updated")
        else
          @categories = ExpenseCategory.manual.ordered
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :edit, status: :unprocessable_entity
        end
      end

      # Deleting removes the row, its treasury movement and its journal entry, so
      # the P&L and the cash flow both stop reporting it. This is the only way to
      # undo a expense: reversal used to be the alternative and is gone, because a
      # reversal left the original on the books and the two reports then had to be
      # read together to see that nothing had really happened.
      def destroy
        authorize @expense

        # Captured before the row goes: an audit entry for a deletion that does not
        # say what was deleted is barely an audit at all, and nothing else survives.
        snapshot = {
          description:  @expense.description,
          amount_cents: @expense.amount_cents,
          date:         @expense.expense_date,
          category:     @expense.expense_category&.name,
          treasury:     @expense.treasury&.name
        }

        @expense.destroy!
        AuditLogEntry.record!(action: "expense.destroy", record: @expense, user: current_user,
                              changes_snapshot: snapshot)

        redirect_to admin_accounting_expenses_path, notice: t("flash.accounting.expense_deleted")
      rescue ArgumentError => e
        redirect_to admin_accounting_expenses_path, alert: e.message
      end

      private

      # Every column an accountant needs to reconcile outside the system. Every
      # row here is live: an undone record is deleted, not flagged, so there is
      # no longer a state the totals leave out.
      def expenses_csv(scope)
        CSV.generate do |csv|
          csv << [
            t("accounting.shared.start"), t("accounting.shared.category"),
            t("accounting.shared.description"), t("accounting.shared.amount"),
            t("accounting.shared.treasury"), t("accounting.shared.reference_number"),
            t("accounting.shared.recorded_by"), t("accounting.export.source")
          ]
          scope.find_each do |record|
            csv << [
              record.expense_date,
              record.expense_category&.name,
              record.description,
              helpers.format_money(record.amount_cents),
              record.treasury&.name,
              record.reference_number,
              record.user&.name,
              record.is_auto_generated? ? t("accounting.shared.auto") : t("accounting.export.manual")
            ]
          end
        end
      end

      PURCHASES_CODES = [5100].freeze
      PAYROLL_CODES   = [
        ::Accounting::JournalEntryService::ADVANCE_CODE,
        ::Accounting::JournalEntryService::SALARY_CODE,
        ::Accounting::JournalEntryService::STAFF_MEAL_CODE
      ].freeze

      def build_ledger_summary(start_date, end_date)
        base = JournalEntryLine.joins(:journal_entry)
          .where(journal_entries: { company_id: Current.company.id })
          .where("account_code >= 5000 AND account_code < 6000")
        base = base.where(journal_entries: { date: start_date.. })  if start_date
        base = base.where(journal_entries: { date: ..end_date })    if end_date

        # Net debit per account code (debit - credit = expense amount). Grouped
        # on the code alone: `account_name` is a snapshot taken when each line
        # was written, so grouping on it too would split one account into two
        # rows the moment the same code was posted under two locales — or after
        # a treasury was renamed.
        totals = base.group(:account_code)
                     .sum("debit_cents - credit_cents")
                     .reject { |_, v| v <= 0 }
        names = base.pluck(:account_code, :account_name).to_h

        purchases_cents = totals.select { |code, _| PURCHASES_CODES.include?(code) }.values.sum
        payroll_cents   = totals.select { |code, _| PAYROLL_CODES.include?(code) }.values.sum
        operations_lines = totals.reject { |code, _| (PURCHASES_CODES + PAYROLL_CODES).include?(code) }
                                 .map { |code, cents|
                                   { code: code,
                                     name: helpers.ledger_account_name(code, names[code]),
                                     cents: cents }
                                 }
                                 .sort_by { |l| l[:code] }
        operations_cents = operations_lines.sum { |l| l[:cents] }

        {
          purchases_cents: purchases_cents,
          payroll_cents:   payroll_cents,
          operations_lines: operations_lines,
          operations_cents: operations_cents,
          total_cents: purchases_cents + payroll_cents + operations_cents
        }
      end

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
