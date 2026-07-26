# frozen_string_literal: true

module Admin
  module Accounting
    # Monthly attendance grid (staff × days). Cells are P/O/A/X; blank = unpaid.
    # Edits autosave one batch at a time via #update and return refreshed per-user
    # summaries so the pay column stays live.
    class AttendanceController < BaseController
      def index
        @payroll_month = parse_month
        @days = (@payroll_month.beginning_of_month..@payroll_month.end_of_month).to_a
        @statuses = AttendanceStatus.active.ordered.to_a
        @staff = staff_scope

        rows = StaffAttendance.for_month(@payroll_month)
          .where(user_id: @staff.map(&:id))
          .includes(:attendance_status)
        @cells = rows.each_with_object({}) { |r, h| h[[r.user_id, r.date]] = r.attendance_status }

        @summaries = @staff.index_with do |user|
          ::Accounting::AttendanceMonthService.new(user, @payroll_month).call
        end
      end

      def update
        month = nil
        affected = []

        (params[:cells] || []).each do |cell|
          user = company_users.find_by(id: cell[:user_id])
          next if user.blank?

          date = cell[:date].to_date
          month ||= date.beginning_of_month
          affected << user
          apply_cell(user, date, cell[:symbol].to_s.strip)
        end

        month ||= parse_month
        summaries = affected.uniq.index_with do |user|
          summary_json(::Accounting::AttendanceMonthService.new(user, month).call)
        end.transform_keys(&:id)

        render json: { ok: true, summaries: summaries }
      rescue ActiveRecord::RecordInvalid, Date::Error, ArgumentError => e
        render json: { ok: false, error: e.message }, status: :unprocessable_entity
      end

      private

      def apply_cell(user, date, symbol)
        if symbol.blank?
          user.staff_attendances.where(date: date).destroy_all
          return
        end

        status = AttendanceStatus.active.find_by(symbol: symbol)
        return if status.nil?

        record = user.staff_attendances.find_or_initialize_by(date: date)
        record.attendance_status = status
        record.recorded_by = current_user
        record.save!
      end

      def staff_scope
        company_users.where("monthly_salary_cents > 0").order(:name)
      end

      def company_users
        User.where(company_id: Current.company.id)
      end

      def summary_json(result)
        {
          payable: format_days(result.payable_days),
          bonus: format_days(result.bonus_days),
          penalty: format_days(result.penalty_days),
          pay: helpers.format_money(result.base_pay_cents)
        }
      end

      def format_days(value)
        helpers.number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
      end

      def parse_month
        if params[:payroll_month].present?
          Date.parse("#{params[:payroll_month]}-01")
        else
          Date.current.beginning_of_month
        end
      rescue ArgumentError
        Date.current.beginning_of_month
      end
    end
  end
end
