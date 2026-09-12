# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class ExpensesController < BaseController
      before_action :set_expense, only: %i[show edit update reverse]

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
        # Reversed rows are excluded from every total on this page, which left no
        # way to look at them. The profit-vs-cash bridge links straight here.
        @reversed_only = params[:reversed] == "1"
        scope = scope.where.not(reversed_at: nil) if @reversed_only

        @total_count    = scope.count
        @reversed_count = scope.where.not(reversed_at: nil).count
        @active_count   = scope.where(reversed_at: nil).count
        active_scope = scope.where(reversed_at: nil).unscope(:includes)
        @total_active_cents  = active_scope.sum(:amount_cents)
        @system_cents        = active_scope.where(is_auto_generated: true).sum(:amount_cents)
        @custom_cents        = active_scope.where(is_auto_generated: false).sum(:amount_cents)

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

      # Every column an accountant needs to reconcile outside the system,
      # including the reversal flag — a reversed row is in the ledger but not in
      # the totals, and an export that hid that would not tie back.
      def expenses_csv(scope)
        CSV.generate do |csv|
          csv << [
            t("accounting.shared.start"), t("accounting.shared.category"),
            t("accounting.shared.description"), t("accounting.shared.amount"),
            t("accounting.shared.treasury"), t("accounting.shared.reference_number"),
            t("accounting.shared.recorded_by"), t("accounting.export.source"),
            t("accounting.export.reversed")
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
              record.is_auto_generated? ? t("accounting.shared.auto") : t("accounting.export.manual"),
              record.reversed_at.present? ? t("accounting.export.reversed_yes") : t("accounting.export.reversed_no")
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

        # net debit per account code (debit - credit = expense amount)
        totals = base.group(:account_code, :account_name)
                     .sum("debit_cents - credit_cents")
                     .reject { |_, v| v <= 0 }

        purchases_cents = totals.select { |(code, _), _| PURCHASES_CODES.include?(code) }.values.sum
        payroll_cents   = totals.select { |(code, _), _| PAYROLL_CODES.include?(code) }.values.sum
        operations_lines = totals.reject { |(code, _), _| (PURCHASES_CODES + PAYROLL_CODES).include?(code) }
                                 .map { |(code, name), cents| { code: code, name: name, cents: cents } }
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
