# frozen_string_literal: true

module Admin
  module Sales
    class PaymentMethodsController < BaseController
      before_action :set_payment_method, only: %i[edit update destroy]

      def index
        @status = params[:status].presence_in(%w[active inactive])
        @q = ::Sales::PaymentMethod.ransack(params[:q])
        @sort = parse_index_sort_param
        @direction = parse_index_sort_direction_param
        @filtered = (params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)) || @status.present?

        scope = @q.result.includes(:treasury)
        scope = scope.where(active: @status == "active") if @status
        scope = scope.order(@sort => @direction, name: :asc)

        @pagy, @payment_methods = pagy(:offset, scope, limit: 25)
      end

      def new
        @payment_method = ::Sales::PaymentMethod.new(active: true)
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def create
        @payment_method = ::Sales::PaymentMethod.new(payment_method_params)
        if @payment_method.save
          redirect_to admin_sales_payment_methods_path, notice: t("sales.payment_methods.flash.created")
        else
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
      end

      def update
        if @payment_method.update(payment_method_params)
          redirect_to admin_sales_payment_methods_path, notice: t("sales.payment_methods.flash.updated")
        else
          @treasuries = Treasury.active.payable.visible_to(current_user).ordered
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        unless @payment_method.deletable?
          redirect_to admin_sales_payment_methods_path, alert: t("sales.payment_methods.flash.cannot_delete")
          return
        end

        @payment_method.destroy!
        redirect_to admin_sales_payment_methods_path, notice: t("sales.payment_methods.flash.deleted")
      end

      private

      def set_payment_method
        @payment_method = ::Sales::PaymentMethod.find(params[:id])
      end

      def payment_method_params
        params.require(:sales_payment_method).permit(:name, :treasury_id, :active)
      end

      def parse_index_sort_param
        sort = params[:sort].to_s
        ::Sales::PaymentMethod::INDEX_SORTABLE_COLUMNS.include?(sort) ? sort : ::Sales::PaymentMethod::INDEX_DEFAULT_SORT
      end

      def parse_index_sort_direction_param
        params[:dir].to_s == "desc" ? "desc" : ::Sales::PaymentMethod::INDEX_DEFAULT_SORT_DIRECTION
      end
    end
  end
end
