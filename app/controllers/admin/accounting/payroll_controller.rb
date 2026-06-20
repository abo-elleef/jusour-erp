# frozen_string_literal: true

require "csv"

module Admin
  module Accounting
    class PayrollController < BaseController
      def index
        load_payroll_rows
        respond_to do |format|
          format.html
          format.csv { send_data generate_payroll_csv, filename: "payroll-week-#{@week_start}.csv" }
        end
      end

      def export
        authorize :accounting, :export?
        load_payroll_rows
        send_data generate_payroll_csv,
          filename: "payroll-week-#{@week_start}.csv",
          type: "text/csv"
      end

      private

      def load_payroll_rows
        @week_start = params[:week_start]&.to_date || Date.current.beginning_of_week
        @week_end = @week_start + 6.days

        @rows = User.active.where(role: %w[cashier manager]).map do |user|
          shifts = ShiftLog.completed
            .where(user: user)
            .where(clocked_in_at: @week_start.beginning_of_day..@week_end.end_of_day)

          total_hours = shifts.sum(&:hours_worked)
          total_tips = shifts.sum(:tips_cents).to_i
          regular_hours = [total_hours, 40.0].min
          ot_hours = [total_hours - 40.0, 0.0].max
          regular_pay = (regular_hours * user.hourly_rate_cents).round
          ot_pay = (ot_hours * user.hourly_rate_cents * 1.5).round

          {
            user: user,
            shifts: shifts.count,
            total_hours: total_hours.round(2),
            regular_hours: regular_hours.round(2),
            ot_hours: ot_hours.round(2),
            regular_pay_cents: regular_pay,
            ot_pay_cents: ot_pay,
            gross_pay_cents: regular_pay + ot_pay,
            tips_cents: total_tips
          }
        end
      end

      def generate_payroll_csv
        CSV.generate(headers: true) do |csv|
          csv << ["Employee", "Shifts", "Total Hours", "Regular Hours", "OT Hours",
                  "Regular Pay", "OT Pay", "Gross Pay", "Tips"]
          @rows.each do |r|
            csv << [
              r[:user].name, r[:shifts], r[:total_hours], r[:regular_hours], r[:ot_hours],
              format_money(r[:regular_pay_cents]), format_money(r[:ot_pay_cents]),
              format_money(r[:gross_pay_cents]), format_money(r[:tips_cents])
            ]
          end
        end
      end
    end
  end
end
