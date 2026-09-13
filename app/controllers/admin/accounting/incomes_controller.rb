# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class IncomesController < BaseController
      before_action :set_income, only: %i[show edit update destroy]

      def show
        authorize @income
        @je = JournalEntry.for_source(@income).includes(:lines).first
        @audits = @income.audits.includes(:user).reorder(version: :desc)
      end

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)
        @q = Income.ransack(params[:q])
        scope = @q.result.includes(:income_category, :user, :treasury)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(is_auto_generated: false) if params[:manual_only] == "1"
        scope = scope.where(income_category_id: params[:category_id]) if params[:category_id].present?

        @total_count = scope.count
        @range_sums = [
          {
            label: t("accounting.incomes.stats_earned"),
            cents: scope.unscope(:includes).sum(:amount_cents),
            tone: :success
          }
        ]
        ordered = scope.order(income_date: :desc, created_at: :desc)

        # CSV exports the whole filtered set, not the page on screen — an export
        # that silently stopped at 50 rows would be worse than none.
        if request.format.csv?
          return send_data incomes_csv(ordered),
            filename: "incomes-#{@start_date}-#{@end_date}.csv",
            type: "text/csv; charset=utf-8"
        end

        @pagy, @incomes = pagy(:offset, ordered, limit: 50)
        @active_category_id = params[:category_id].presence
        @totals_by_category = Income.joins(:income_category)
          .on_date_range(@start_date, @end_date)
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
        @categories = IncomeCategory.manual.ordered
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def update
        authorize @income
        if @income.update(income_params)
          redirect_to admin_accounting_incomes_path, notice: t("flash.accounting.income_updated")
        else
          @categories = IncomeCategory.manual.ordered
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :edit, status: :unprocessable_entity
        end
      end

      # Deleting removes the row, its treasury movement and its journal entry, so
      # the P&L and the cash flow both stop reporting it. This is the only way to
      # undo a income: reversal used to be the alternative and is gone, because a
      # reversal left the original on the books and the two reports then had to be
      # read together to see that nothing had really happened.
      def destroy
        authorize @income

        # Captured before the row goes: an audit entry for a deletion that does not
        # say what was deleted is barely an audit at all, and nothing else survives.
        snapshot = {
          description:  @income.description,
          amount_cents: @income.amount_cents,
          date:         @income.income_date,
          category:     @income.income_category&.name,
          treasury:     @income.treasury&.name
        }

        @income.destroy!
        AuditLogEntry.record!(action: "income.destroy", record: @income, user: current_user,
                              changes_snapshot: snapshot)

        redirect_to admin_accounting_incomes_path, notice: t("flash.accounting.income_deleted")
      rescue ArgumentError => e
        redirect_to admin_accounting_incomes_path, alert: e.message
      end

      private

      # Every column an accountant needs to reconcile outside the system. Every
      # row here is live: an undone record is deleted, not flagged, so there is
      # no longer a state the totals leave out.
      def incomes_csv(scope)
        CSV.generate do |csv|
          csv << [
            t("accounting.shared.start"), t("accounting.shared.category"),
            t("accounting.shared.description"), t("accounting.shared.amount"),
            t("accounting.shared.treasury"), t("accounting.shared.reference_number"),
            t("accounting.shared.recorded_by"), t("accounting.export.source")
          ]
          scope.find_each do |record|
            csv << [
              record.income_date,
              record.income_category&.name,
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
