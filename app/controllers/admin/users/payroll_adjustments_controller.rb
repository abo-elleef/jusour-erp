# frozen_string_literal: true

module Admin
  module Users
    class PayrollAdjustmentsController < BaseController
      before_action :set_user
      before_action :set_adjustment, only: :destroy

      def create
        @adjustment = @user.payroll_adjustments.build(adjustment_params)
        @adjustment.recorded_by = current_user
        authorize @adjustment

        if @adjustment.save
          redirect_to admin_user_path(@user, payroll_show_url_params(@adjustment.payroll_month)),
            notice: t("flash.payroll_adjustment.created")
        else
          redirect_to admin_user_path(@user, payroll_show_url_params(adjustment_params[:payroll_month])),
            alert: @adjustment.errors.full_messages.to_sentence
        end
      end

      def destroy
        authorize @adjustment
        month = @adjustment.payroll_month
        @adjustment.destroy!
        redirect_to admin_user_path(@user, payroll_show_url_params(month)),
          notice: t("flash.payroll_adjustment.removed")
      end

      private

      def set_user
        @user = User.find(params[:user_id])
      end

      def set_adjustment
        @adjustment = @user.payroll_adjustments.find(params[:id])
      end

      def adjustment_params
        params.require(:payroll_adjustment).permit(
          :kind, :unit_type, :amount_pounds, :overtime_hours, :payroll_month, :happened_at, :notes
        )
      end

      def payroll_show_url_params(month)
        {
          payroll_month: month,
          payroll_sort: params[:payroll_sort].presence,
          payroll_direction: params[:payroll_direction].presence
        }.compact
      end
    end
  end
end
