# frozen_string_literal: true

module Admin
  module Accounting
    class ShiftLogsController < BaseController
      before_action :set_shift, only: %i[show clock_out]

      def index
        @date = params[:date]&.to_date || Date.current
        @shifts = policy_scope(ShiftLog)
          .where(clocked_in_at: @date.beginning_of_day..@date.end_of_day)
          .includes(:user)
          .order(clocked_in_at: :desc)
      end

      def show
        authorize @shift
      end

      def clock_in
        authorize ShiftLog, :clock_in?
        if current_user.clocked_in?
          return redirect_to admin_accounting_shift_logs_path, alert: t("flash.accounting.already_clocked_in")
        end

        shift = ShiftLog.create!(
          user: current_user,
          clocked_in_at: Time.current,
          hourly_rate_cents: current_user.hourly_rate_cents,
          status: "active"
        )
        AuditLogEntry.record!(action: "shift.clock_in", record: shift, user: current_user)
        redirect_to admin_accounting_shift_logs_path,
          notice: t("flash.accounting.clocked_in", time: l(Time.current, format: :short_time))
      end

      def clock_out
        authorize @shift, :clock_out?
        ::Accounting::ClockOutService.new(@shift, user: current_user).call
        redirect_to admin_accounting_shift_logs_path, notice: t("flash.accounting.clocked_out")
      end

      private

      def set_shift
        @shift = ShiftLog.find(params[:id])
      end
    end
  end
end
