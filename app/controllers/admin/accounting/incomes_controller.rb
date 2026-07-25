# frozen_string_literal: true

module Admin
  module Accounting
    class IncomesController < BaseController
      before_action :set_income, only: %i[show edit update reverse]

      def show
        authorize @income
        @je = JournalEntry.for_source(@income).includes(:lines).first
      end

      def index
        parse_date_range
        @q = Income.ransack(params[:q])
        scope = @q.result.includes(:income_category, :user, :treasury)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(is_auto_generated: false) if params[:manual_only] == "1"
        scope = scope.where(income_category_id: params[:category_id]) if params[:category_id].present?

        @total_count    = scope.count
        @reversed_count = scope.where.not(reversed_at: nil).count
        @active_count   = scope.where(reversed_at: nil).count
        @pagy, @incomes = pagy(:offset, scope.order(income_date: :desc, created_at: :desc), limit: 50)
        @active_category_id = params[:category_id].presence
        @totals_by_category = Income.joins(:income_category)
          .on_date_range(@start_date, @end_date)
          .where(reversed_at: nil)
          .group("income_categories.id", "income_categories.name")
          .sum(:amount_cents)
        @categories = IncomeCategory.ordered
      end

      def new
        @income = Income.new(income_date: Date.current, user: current_user, treasury: Treasury.default_treasury)
        authorize @income
        @categories = IncomeCategory.manual.ordered
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def create
        @income = Income.new(income_params.merge(user: current_user, is_auto_generated: false))
        authorize @income

        if @income.save
          redirect_to admin_accounting_incomes_path, notice: t("flash.accounting.income_recorded")
        else
          @categories = IncomeCategory.manual.ordered
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @income
        if @income.reversed_at.present?
          return redirect_to admin_accounting_incomes_path,
                             alert: t("accounting.reversal.cannot_edit_reversed")
        end
        @categories = IncomeCategory.manual.ordered
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def update
        authorize @income
        if @income.reversed_at.present?
          return redirect_to admin_accounting_incomes_path,
                             alert: t("accounting.reversal.cannot_edit_reversed")
        end
        if @income.update(income_params)
          redirect_to admin_accounting_incomes_path, notice: t("flash.accounting.income_updated")
        else
          @categories = IncomeCategory.manual.ordered
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :edit, status: :unprocessable_entity
        end
      end

      def reverse
        authorize @income, :destroy?
        je = JournalEntry.for_source(@income).first

        if je.nil?
          return redirect_to admin_accounting_incomes_path,
                             alert: t("accounting.reversal.no_journal_entry")
        end

        if @income.reversed_at.present? || je.reversed?
          return redirect_to admin_accounting_incomes_path,
                             alert: t("accounting.reversal.already_reversed")
        end

        ActiveRecord::Base.transaction do
          reversal = ::Accounting::JournalEntryService.record_reversal!(
            original_je: je, user: current_user
          )
          sync_je_treasuries!(reversal)
          @income.update_column(:reversed_at, Time.current)
          AuditLogEntry.record!(action: "income.reverse", record: @income, user: current_user)
        end

        redirect_to admin_accounting_incomes_path,
                    notice: t("accounting.reversal.income_reversed")
      end

      private

      def set_income
        @income = Income.find(params[:id])
      end

      def income_params
        params.require(:income).permit(
          :income_category_id, :treasury_id, :description, :amount_pounds, :income_date,
          :recurrence, :reference_number, :receipt_image
        )
      end
    end
  end
end
