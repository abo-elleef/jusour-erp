# frozen_string_literal: true

module Admin
  module Accounting
    class IncomeCategoriesController < BaseController
      before_action :set_category, only: %i[edit update destroy]

      def index
        @q = IncomeCategory.ransack(params[:q])
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @categories = @q.result.ordered
        @category_types = IncomeCategory::CATEGORY_TYPES
        @sortable = !@filtered
      end

      def reorder
        authorize IncomeCategory, :update?, policy_class: AccountingPolicy
        positions = params[:positions].presence || JSON.parse(request.body.read).fetch("positions")
        positions.each do |id, position|
          IncomeCategory.where(id: id).update_all(position: position.to_i)
        end
        head :ok
      end

      def new
        @category = IncomeCategory.new
        authorize @category, :create?, policy_class: AccountingPolicy
      end

      def create
        @category = IncomeCategory.new(category_params)
        authorize @category, :create?, policy_class: AccountingPolicy

        if @category.save
          redirect_to admin_accounting_income_categories_path, notice: t("flash.accounting.income_category_created")
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        authorize @category, :update?, policy_class: AccountingPolicy
      end

      def update
        authorize @category, :update?, policy_class: AccountingPolicy
        if @category.update(category_params)
          redirect_to admin_accounting_income_categories_path, notice: t("flash.accounting.income_category_updated")
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @category, :destroy?, policy_class: AccountingPolicy
        if @category.system_managed?
          redirect_to admin_accounting_income_categories_path, alert: t("flash.accounting.income_category_system_delete")
        else
          @category.destroy!
          redirect_to admin_accounting_income_categories_path, notice: t("flash.accounting.income_category_removed")
        end
      end

      private

      def set_category
        @category = IncomeCategory.find(params[:id])
      end

      def category_params
        params.require(:income_category).permit(:name, :category_type, :position)
      end
    end
  end
end
