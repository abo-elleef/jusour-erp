# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class MonthlyPayrollController < BaseController
      def index
        @payroll_month = parse_payroll_month
        @sort = parse_index_sort_param
        @sort_direction = parse_index_sort_direction_param
        @rows = sorted_payroll_rows
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
        @sort = parse_index_sort_param
        @sort_direction = parse_index_sort_direction_param
        @rows = sorted_payroll_rows
        send_data generate_csv,
          filename: "monthly-payroll-#{@payroll_month.strftime('%Y-%m')}.csv",
          type: "text/csv"
      end

      private

      def sorted_payroll_rows
        rows = ::Accounting::MonthlyPayrollService.for_all_staff(@payroll_month)
        ::Accounting::MonthlyPayrollService.sort_rows(rows, sort: @sort, direction: @sort_direction)
      end

      def parse_index_sort_param
        sort = params[:sort].to_s
        ::Accounting::MonthlyPayrollService::INDEX_SORTABLE_COLUMNS.include?(sort) ? sort : ::Accounting::MonthlyPayrollService::INDEX_DEFAULT_SORT
      end

      def parse_index_sort_direction_param
        params[:direction].to_s == "desc" ? "desc" : ::Accounting::MonthlyPayrollService::INDEX_DEFAULT_SORT_DIRECTION
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
