# frozen_string_literal: true

module Admin
  module Accounting
    class IncomesController < BaseController
      before_action :set_income, only: %i[edit update destroy]

      def index
        parse_date_range
        @q = Income.ransack(params[:q])
        scope = @q.result.includes(:income_category, :user, :treasury)
        scope = scope.on_date_range(@start_date, @end_date)
        scope = scope.where(is_auto_generated: false) if params[:manual_only] == "1"
        scope = scope.where(income_category_id: params[:category_id]) if params[:category_id].present?

        @incomes = scope.order(income_date: :desc, created_at: :desc).limit(200)
        @totals_by_category = Income.joins(:income_category)
          .on_date_range(@start_date, @end_date)
          .group("income_categories.name")
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

      def destroy
        authorize @income
        AuditLogEntry.record!(action: "income.delete", record: @income, user: current_user)
        @income.destroy!
        redirect_to admin_accounting_incomes_path, notice: t("flash.accounting.income_removed")
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
