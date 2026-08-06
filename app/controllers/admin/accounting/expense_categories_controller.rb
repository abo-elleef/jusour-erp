# frozen_string_literal: true

module Admin
  module Accounting
    class ExpenseCategoriesController < BaseController
      before_action :set_category, only: %i[edit update destroy]

      def index
        @q = ExpenseCategory.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @categories = @q.result.ordered
        @category_types = ExpenseCategory::CATEGORY_TYPES
        @sortable = !@filtered
      end

      def reorder
        authorize ExpenseCategory, :update?, policy_class: AccountingPolicy
        positions = params[:positions].presence || JSON.parse(request.body.read).fetch("positions")
        positions.each do |id, position|
          ExpenseCategory.where(id: id).update_all(position: position.to_i)
        end
        head :ok
      end

      def new
        @category = ExpenseCategory.new
        authorize @category, :create?, policy_class: AccountingPolicy
      end

      def create
        @category = ExpenseCategory.new(category_params)
        authorize @category, :create?, policy_class: AccountingPolicy

        if @category.save
          redirect_to admin_accounting_expense_categories_path, notice: t("flash.accounting.category_created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @category, :update?, policy_class: AccountingPolicy
        @audits = @category.audits.includes(:user).reorder(version: :desc)
      end

      def update
        authorize @category, :update?, policy_class: AccountingPolicy
        if @category.update(category_params)
          redirect_to admin_accounting_expense_categories_path, notice: t("flash.accounting.category_updated")
        else
          @audits = @category.audits.includes(:user).reorder(version: :desc)
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @category, :destroy?, policy_class: AccountingPolicy
        if @category.system_managed?
          redirect_to admin_accounting_expense_categories_path, alert: t("flash.accounting.category_system_delete")
        else
          @category.destroy!
          redirect_to admin_accounting_expense_categories_path, notice: t("flash.accounting.category_removed")
        end
      end

      private

      def set_category
        @category = ExpenseCategory.find(params[:id])
      end

      def category_params
        params.require(:expense_category).permit(:name, :category_type, :position)
      end
    end
  end
end
