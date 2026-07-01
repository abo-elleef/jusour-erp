# frozen_string_literal: true

module Admin
  module Accounting
    class PaymentMethodTreasuriesController < BaseController
      def index
        authorize PaymentMethodTreasury
        @mappings = PaymentMethodTreasury::SUPPORTED_METHODS.index_with do |method|
          PaymentMethodTreasury.find_by(payment_method: method)
        end
        @treasuries = Treasury.ordered
      end

      def create
        authorize PaymentMethodTreasury

        if permitted_params[:treasury_id].blank?
          return redirect_to admin_accounting_payment_method_treasuries_path,
                             alert: t("admin.accounting.payment_method_treasuries.select_treasury")
        end

        mapping = PaymentMethodTreasury.find_or_initialize_by(payment_method: permitted_params[:payment_method])
        mapping.treasury_id = permitted_params[:treasury_id]

        if mapping.save
          redirect_to admin_accounting_payment_method_treasuries_path,
                      notice: t("admin.accounting.payment_method_treasuries.saved")
        else
          redirect_to admin_accounting_payment_method_treasuries_path,
                      alert: mapping.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize PaymentMethodTreasury
        mapping = PaymentMethodTreasury.find_by!(payment_method: params[:id])
        mapping.destroy!
        redirect_to admin_accounting_payment_method_treasuries_path,
                    notice: t("admin.accounting.payment_method_treasuries.removed")
      end

      private

      def permitted_params
        params.require(:payment_method_treasury).permit(:payment_method, :treasury_id)
      end
    end
  end
end
