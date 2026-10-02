# frozen_string_literal: true

module Accounting
  # Turns a staff member's attendance for a month into their base salary for that
  # month, using the daily-rate = salary/30 (Egypt) convention with a build-up
  # model (no hire/leave dates needed — blank days simply aren't paid).
  #
  #   base_pay = fully_paid_month ? full salary
  #                               : (payable_days - penalty_days) * (salary / 30)
  #
  # "Fully paid month" (every calendar day a paid status) short-circuits to the
  # full salary so a present 28- or 31-day month still pays exactly the monthly
  # salary rather than 28/30 or 31/30.
  class AttendanceMonthService
    Result = Struct.new(
      :user,
      :payroll_month,
      :days_in_month,
      :marked_days,
      :payable_days,
      :bonus_days,
      :penalty_days,
      :fully_paid_month,
      :base_pay_cents,
      keyword_init: true
    )

    def initialize(user, payroll_month)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
    end

    def call
      # .recorded excludes cleared rows (nil status, kept only for their audit
      # trail) — a cleared day counts the same as no row at all.
      records = @user.staff_attendances.for_month(@payroll_month).recorded.includes(:attendance_status).to_a

      payable  = records.sum { |r| r.attendance_status.paid_fraction.to_d }
      bonus    = records.sum { |r| r.attendance_status.bonus_days.to_d }
      penalty  = records.sum { |r| r.attendance_status.penalty_days.to_d }
      in_month = @payroll_month.end_of_month.day
      salary   = @user.monthly_salary_cents.to_i
      rate     = @user.daily_rate_cents # salary / 30
      full     = payable == in_month

      # Full month → the salary already represents every day paid, so bonuses
      # (and any penalties, though a full month has none) apply on top.
      base_pay = if full
                   [salary + ((bonus - penalty) * rate).round, 0].max
                 else
                   [((payable + bonus - penalty) * rate).round, 0].max
                 end

      Result.new(
        user: @user,
        payroll_month: @payroll_month,
        days_in_month: in_month,
        marked_days: records.size,
        payable_days: payable,
        bonus_days: bonus,
        penalty_days: penalty,
        fully_paid_month: full,
        base_pay_cents: base_pay
      )
    end
  end
end
