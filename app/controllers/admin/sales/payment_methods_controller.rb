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

        scope = @q.result.includes(:treasury, :approvers)
        scope = scope.where(active: @status == "active") if @status
        scope = scope.order(@sort => @direction, name: :asc)

        @pagy, @payment_methods = pagy(:offset, scope, limit: 25)
      end

      def new
        @payment_method = ::Sales::PaymentMethod.new(active: true, requires_approval: true)
        load_form_data
      end

      def create
        @payment_method = ::Sales::PaymentMethod.new(payment_method_params)
        if save_with_approvers(@payment_method)
          redirect_to admin_sales_payment_methods_path, notice: t("sales.payment_methods.flash.created")
        else
          load_form_data
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        load_form_data
      end

      def update
        @payment_method.assign_attributes(payment_method_params)
        if save_with_approvers(@payment_method)
          redirect_to admin_sales_payment_methods_path, notice: t("sales.payment_methods.flash.updated")
        else
          load_form_data
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
        params.require(:sales_payment_method).permit(:name, :treasury_id, :active, :requires_approval, :requires_proof_image)
      end

      def load_form_data
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
        @eligible_approvers = eligible_approvers
      end

      # Only people who can open the sales area can act on an approval.
      def eligible_approvers
        User.where(company_id: Current.company.id).active.order(:name).select { |u| u.can?("customers:manage") }
      end

      # Approvers are replaced as a set; ids outside the eligible list are dropped.
      def save_with_approvers(payment_method)
        submitted = Array(params.dig(:sales_payment_method, :approver_ids)).compact_blank
        allowed = eligible_approvers.map(&:id).map(&:to_s)
        ::Sales::PaymentMethod.transaction do
          payment_method.save!
          payment_method.approver_ids = submitted & allowed
        end
        true
      rescue ActiveRecord::RecordInvalid
        false
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
