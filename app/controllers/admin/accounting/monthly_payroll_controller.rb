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
        @treasuries = Treasury.active.payable.visible_to(current_user).ordered
        @default_treasury = Treasury.default_treasury

        respond_to do |format|
          format.html
          format.csv { send_data generate_csv, filename: "monthly-payroll-#{@payroll_month.strftime('%Y-%m')}.csv" }
        end
      end

      def finalize_all
        authorize PayrollSnapshot, :create?

        @payroll_month = parse_payroll_month
        treasury = resolve_bulk_treasury
        paid_on = bulk_paid_on
        finalized = 0

        ::Accounting::MonthlyPayrollService.for_all_staff(@payroll_month).each do |row|
          next unless row.user.active?
          next if row.finalized

          ::Accounting::FinalizePayrollService.new(
            row.user,
            @payroll_month,
            finalized_by: current_user,
            treasury: treasury,
            paid_on: paid_on
          ).call
          finalized += 1
        end

        notice = finalized.positive? ? t("flash.payroll_snapshot.bulk_recorded", count: finalized) : t("flash.payroll_snapshot.all_recorded")
        redirect_to admin_accounting_monthly_payroll_path(payroll_month: @payroll_month.strftime("%Y-%m")), notice: notice
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_accounting_monthly_payroll_path(payroll_month: @payroll_month.strftime("%Y-%m")),
          alert: e.record.errors.full_messages.to_sentence
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

      def resolve_bulk_treasury
        treasury_id = params.dig(:payroll_snapshot, :treasury_id)
        return if treasury_id.blank?

        Treasury.active.payable.visible_to(current_user).find(treasury_id)
      end

      def bulk_paid_on
        params.dig(:payroll_snapshot, :paid_on)
      end

      def generate_csv
        CSV.generate(headers: true) do |csv|
          csv << [
            t("accounting.shift_logs.employee"),
            t("accounting.monthly_payroll.base_salary"),
            t("accounting.monthly_payroll.daily_rate"),
            t("accounting.monthly_payroll.penalties"),
            t("accounting.monthly_payroll.bonuses"),
            t("accounting.monthly_payroll.net_pay"),
            t("accounting.monthly_payroll.advances"),
            t("accounting.monthly_payroll.remaining_pay")
          ]
          @rows.each do |row|
            csv << [
              row.user.name,
              amount(row.base_salary_cents),
              amount(row.daily_rate_cents),
              amount(row.penalties_cents),
              amount(row.bonuses_cents),
              amount(row.net_pay_cents),
              amount(row.advances_cents),
              amount(row.remaining_pay_cents)
            ]
          end

          next if @rows.empty?

          csv << [
            t("accounting.monthly_payroll.totals"),
            amount(@rows.sum(&:base_salary_cents)),
            "",
            amount(@rows.sum(&:penalties_cents)),
            amount(@rows.sum(&:bonuses_cents)),
            amount(@rows.sum(&:net_pay_cents)),
            amount(@rows.sum(&:advances_cents)),
            amount(@rows.sum(&:remaining_pay_cents))
          ]
        end
      end

      # Plain numeric amount for CSV — no currency symbol or thousands separators.
      def amount(cents)
        format("%.2f", cents.to_i / 100.0)
      end
    end
  end
end
