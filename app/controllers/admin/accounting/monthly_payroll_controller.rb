# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class MonthlyPayrollController < BaseController
      def index
        @payroll_month = parse_payroll_month
        @rows = ::Accounting::MonthlyPayrollService.for_all_staff(@payroll_month)
        @finalized_count = @rows.count(&:finalized)
        @pending_count = @rows.count - @finalized_count

        respond_to do |format|
          format.html
          format.csv { send_data generate_csv, filename: "monthly-payroll-#{@payroll_month.strftime('%Y-%m')}.csv" }
        end
      end

      def finalize_all
        authorize PayrollSnapshot, :create?

        @payroll_month = parse_payroll_month
        finalized = 0

        ::Accounting::MonthlyPayrollService.for_all_staff(@payroll_month).each do |row|
          next if row.finalized

          ::Accounting::FinalizePayrollService.new(row.user, @payroll_month, finalized_by: current_user).call
          finalized += 1
        end

        notice = finalized.positive? ? t("flash.payroll_snapshot.bulk_recorded", count: finalized) : t("flash.payroll_snapshot.all_recorded")
        redirect_to admin_accounting_monthly_payroll_path(payroll_month: @payroll_month.strftime("%Y-%m")), notice: notice
      end

      def export
        authorize :accounting, :export?
        @payroll_month = parse_payroll_month
        @rows = ::Accounting::MonthlyPayrollService.for_all_staff(@payroll_month)
        send_data generate_csv,
          filename: "monthly-payroll-#{@payroll_month.strftime('%Y-%m')}.csv",
          type: "text/csv"
      end

      private

      def parse_payroll_month
        if params[:payroll_month].present?
          Date.parse("#{params[:payroll_month]}-01")
        else
          Date.current.beginning_of_month
        end
      rescue ArgumentError
        Date.current.beginning_of_month
      end

      def generate_csv
        CSV.generate(headers: true) do |csv|
          csv << [
            t("accounting.shift_logs.employee"),
            t("accounting.monthly_payroll.base_salary"),
            t("accounting.monthly_payroll.daily_rate"),
            t("accounting.monthly_payroll.penalties"),
            t("accounting.monthly_payroll.bonuses"),
            t("accounting.monthly_payroll.net_pay")
          ]
          @rows.each do |row|
            csv << [
              row.user.name,
              format_money(row.base_salary_cents),
              format_money(row.daily_rate_cents),
              format_money(row.penalties_cents),
              format_money(row.bonuses_cents),
              format_money(row.net_pay_cents)
            ]
          end
        end
      end
    end
  end
end
