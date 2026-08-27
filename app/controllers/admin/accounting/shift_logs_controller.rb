# frozen_string_literal: true

module Admin
  module Accounting
    class ShiftLogsController < BaseController
      before_action { require_feature!(:attendance) }
      before_action :set_shift, only: %i[show clock_out]

      def index
        @date = params[:date]&.to_date || BusinessDay.today
        @shifts = policy_scope(ShiftLog)
          .where(clocked_in_at: BusinessDay.range(@date))
          .includes(:user)
          .order(clocked_in_at: :desc)

        # Per-shift completed-order count + sales total. One aggregate query per
        # shift; the set is a single day's shifts, so N stays small.
        @order_stats = @shifts.each_with_object({}) do |shift, stats|
          count, total = shift.orders.completed.pick(
            Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(total_cents), 0)")
          )
          stats[shift.id] = { count: count.to_i, total_cents: total.to_i }
        end
      end

      def show
        authorize @shift

        @orders = @shift.orders
          .includes(:customer, :payments, :order_items)
          .order(created_at: :desc)

        @completed_orders  = @orders.select { |o| o.status == "completed" }
        @gross_sales_cents = @completed_orders.sum { |o| o.total_cents.to_i }
        @avg_order_cents   = @completed_orders.any? ? (@gross_sales_cents / @completed_orders.size) : 0

        settled = @orders.flat_map(&:payments)
                         .select { |p| %w[completed partially_refunded].include?(p.status) }
        @collected_cents    = settled.sum(&:amount_cents)
        @payments_by_method = settled.group_by(&:payment_method)
                                     .transform_values { |ps| ps.sum(&:amount_cents) }
                                     .sort_by { |_method, cents| -cents }

        @sales_summary = ::Accounting::SessionSalesSummary.for_user_window(
          user_id: @shift.user_id,
          start_time: @shift.clocked_in_at,
          end_time: @shift.orders_ended_at
        )

        @drawer_session = CashDrawerSession
          .where(user_id: @shift.user_id, session_date: BusinessDay.for(@shift.clocked_in_at))
          .order(created_at: :desc)
          .first
        if @drawer_session
          @drawer_sales_summary = ::Accounting::SessionSalesSummary.for_session(@drawer_session)
        end
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
