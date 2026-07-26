# frozen_string_literal: true

module Admin
  module Accounting
    class DashboardController < BaseController
      def index
        today = BusinessDay.today
        month_start = today.beginning_of_month

        @today_report = ::Accounting::SalesReportService.new(today, today).call
        @month_report = ::Accounting::SalesReportService.new(month_start, today).call
        @chart_report = ::Accounting::SalesReportService.new(30.days.ago.to_date, today).call
        @pnl_month = ::Accounting::PnlService.new(month_start, today).call
        @food_cost = ::Accounting::FoodCostService.new(month_start, today).call
        @open_cash_sessions = CashDrawerSession.open.where(session_date: today).includes(:user)

        @ot_warnings = User.where(role: %w[cashier manager]).filter_map do |user|
          checker = ::Accounting::OvertimeCheckService.new(user)
          next unless checker.approaching_overtime? || checker.over_overtime?

          { user: user, hours: checker.weekly_hours.round(1), over: checker.over_overtime? }
        end
      end
    end
  end
end
