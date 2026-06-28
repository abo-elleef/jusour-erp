# frozen_string_literal: true

module Admin
  module Users
    class PayrollAdvancesController < BaseController
      before_action :set_user
      before_action :set_advance, only: :destroy

      def create
        authorize PayrollAdvance

        payroll_month = parse_payroll_month
        ::Accounting::PayPayrollAdvanceService.new(
          user: @user,
          payroll_month: payroll_month,
          advance_slot: advance_params[:advance_slot],
          amount_cents: (advance_params[:amount_pounds].to_f * 100).round,
          treasury: Treasury.find(advance_params[:treasury_id]),
          paid_by: current_user,
          paid_on: advance_params[:paid_on].presence || Date.current,
          notes: advance_params[:notes]
        ).call

        redirect_to admin_user_path(@user, payroll_show_url_params(payroll_month)),
          notice: t("flash.payroll_advance.paid")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_user_path(@user, payroll_show_url_params(payroll_month)),
          alert: e.record.errors.full_messages.to_sentence
      end

      def destroy
        authorize @advance
        month = @advance.payroll_month

        ApplicationRecord.transaction do
          ::Accounting::TreasuryLedgerService.remove_source!(@advance)
          @advance.destroy!
        end

        redirect_to admin_user_path(@user, payroll_show_url_params(month)),
          notice: t("flash.payroll_advance.removed")
      end

      private

      def set_user
        @user = User.find(params[:user_id])
      end

      def set_advance
        @advance = @user.payroll_advances.find(params[:id])
      end

      def parse_payroll_month
        if params.dig(:payroll_advance, :payroll_month).present?
          Date.parse("#{params[:payroll_advance][:payroll_month]}-01")
        elsif params[:payroll_month].present?
          Date.parse("#{params[:payroll_month]}-01")
        else
          Date.current.beginning_of_month
        end
      rescue ArgumentError
        Date.current.beginning_of_month
      end

      def advance_params
        params.require(:payroll_advance).permit(:amount_pounds, :treasury_id, :paid_on, :advance_slot, :notes)
      end

      def payroll_show_url_params(month)
        {
          payroll_month: month.to_date.beginning_of_month.strftime("%Y-%m"),
          payroll_sort: params[:payroll_sort].presence,
          payroll_direction: params[:payroll_direction].presence
        }.compact
      end
    end
  end
end
