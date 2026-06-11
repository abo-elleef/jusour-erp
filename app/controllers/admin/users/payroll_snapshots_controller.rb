# frozen_string_literal: true

module Admin
  module Users
    class PayrollSnapshotsController < BaseController
      before_action :set_user

      def create
        authorize PayrollSnapshot

        payroll_month = parse_payroll_month
        ::Accounting::FinalizePayrollService.new(@user, payroll_month, finalized_by: current_user).call

        redirect_to redirect_path(payroll_month), notice: t("flash.payroll_snapshot.recorded")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to redirect_path(payroll_month), alert: e.record.errors.full_messages.to_sentence
      end

      def destroy
        payroll_month = parse_payroll_month
        snapshot = @user.payroll_snapshots.find_by!(payroll_month: payroll_month)
        authorize snapshot
        snapshot.destroy!

        redirect_to redirect_path(payroll_month), notice: t("flash.payroll_snapshot.undone")
      end

      private

      def set_user
        @user = User.find(params[:user_id])
      end

      def parse_payroll_month
        if params[:payroll_month].present?
          Date.parse("#{params[:payroll_month]}-01")
        else
          Date.current.beginning_of_month
        end
      rescue ArgumentError
        Date.current.beginning_of_month
      end

      def redirect_path(payroll_month)
        month_param = payroll_month.strftime("%Y-%m")

        case params[:return_to]
        when "index"
          admin_users_path
        when "monthly_payroll"
          admin_accounting_monthly_payroll_path(payroll_month: month_param)
        else
          admin_user_path(@user, payroll_month: month_param)
        end
      end
    end
  end
end
