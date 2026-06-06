# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class MonthlyPayrollController < BaseController
      def index
        @payroll_month = parse_payroll_month
        @rows = Accounting::MonthlyPayrollService.for_all_staff(@payroll_month)

        respond_to do |format|
          format.html
          format.csv { send_data generate_csv, filename: "monthly-payroll-#{@payroll_month.strftime('%Y-%m')}.csv" }
        end
      end

      def export
        authorize :accounting, :export?
        @payroll_month = parse_payroll_month
        @rows = Accounting::MonthlyPayrollService.for_all_staff(@payroll_month)
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
