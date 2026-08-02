# frozen_string_literal: true

module Accounting
  class MonthlyPayrollService
    INDEX_SORTABLE_COLUMNS = %w[
      name base_salary_cents daily_rate_cents penalties_cents bonuses_cents
      net_pay_cents advances_cents staff_meals_cents remaining_pay_cents status
    ].freeze
    INDEX_DEFAULT_SORT = "name"
    INDEX_DEFAULT_SORT_DIRECTION = "asc"

    Result = Struct.new(
      :user,
      :payroll_month,
      :base_salary_cents,
      :attendance_pay_cents,
      :attendance_recorded,
      :payable_days,
      :bonus_days,
      :penalty_days,
      :daily_rate_cents,
      :penalties_cents,
      :bonuses_cents,
      :net_pay_cents,
      :advances_cents,
      :staff_meals_cents,
      :remaining_pay_cents,
      :adjustments,
      :advances,
      :finalized,
      :snapshot,
      keyword_init: true
    )

    def initialize(user, payroll_month, sort: nil, direction: nil)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @sort = PayrollAdjustment::SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : PayrollAdjustment::DEFAULT_SORT
      @direction = direction.to_s == "asc" ? :asc : :desc
    end

    def call
      built = build_calculated
      snapshot = PayrollSnapshot.find_by(user: @user, payroll_month: @payroll_month)
      return with_snapshot(built, snapshot) if snapshot

      built
    end

    def build_calculated
      adjustments    = sorted_adjustments
      advances       = @user.payroll_advances.for_month(@payroll_month).ordered
      full_salary    = @user.monthly_salary_cents.to_i

      # Attendance drives the base pay only for attendance-paid roles
      # (cashier/kitchen); everyone else keeps their fixed monthly salary. If a
      # month has nothing recorded, fall back to the full salary so legacy months
      # are unaffected until the grid is used.
      attendance     = AttendanceMonthService.new(@user, @payroll_month).call
      recorded       = @user.attendance_paid? && attendance.marked_days.positive?
      attendance_pay = recorded ? attendance.base_pay_cents : full_salary

      penalties      = adjustments.penalties.sum(:amount_cents)
      bonuses        = adjustments.bonuses.sum(:amount_cents)
      gross_net      = attendance_pay - penalties + bonuses
      advances_total = advances.sum(:amount_cents)
      meals_total    = staff_meals_for_month

      Result.new(
        user: @user,
        payroll_month: @payroll_month,
        base_salary_cents: full_salary,
        attendance_pay_cents: attendance_pay,
        attendance_recorded: recorded,
        payable_days: attendance.payable_days,
        bonus_days: attendance.bonus_days,
        penalty_days: attendance.penalty_days,
        daily_rate_cents: @user.daily_rate_cents,
        penalties_cents: penalties,
        bonuses_cents: bonuses,
        net_pay_cents: gross_net,
        advances_cents: advances_total,
        staff_meals_cents: meals_total,
        remaining_pay_cents: gross_net - advances_total - meals_total,
        adjustments: adjustments,
        advances: advances,
        finalized: false,
        snapshot: nil
      )
    end

    def self.for_all_staff(payroll_month, users: User.active)
      snapshots = PayrollSnapshot.for_month(payroll_month).index_by(&:user_id)

      users.order(:name).filter_map do |user|
        next unless payroll_row?(user, payroll_month, snapshots[user.id])

        new(user, payroll_month).call
      end
    end

    def self.payroll_row?(user, payroll_month, snapshot)
      return true if snapshot

      user.monthly_salary_cents.to_i.positive? ||
        user.payroll_adjustments.for_month(payroll_month).exists? ||
        user.payroll_advances.for_month(payroll_month).exists?
    end

    def self.sort_rows(rows, sort:, direction:)
      sort = INDEX_SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : INDEX_DEFAULT_SORT
      direction = direction.to_s == "desc" ? :desc : :asc

      sorted = case sort
               when "name"
                 rows.sort_by { |row| row.user.name.downcase }
               when "status"
                 rows.sort_by { |row| row.finalized ? 1 : 0 }
               else
                 rows.sort_by { |row| row.public_send(sort).to_i }
               end

      direction == :desc ? sorted.reverse : sorted
    end

    private

    def staff_meals_for_month
      month_start = @payroll_month.beginning_of_month.beginning_of_day
      month_end   = @payroll_month.end_of_month.end_of_day

      Payment
        .joins(:order)
        .where(payment_method: "staff_deduction", status: "completed")
        .where(orders: { staff_meal_user_id: @user.id, company_id: @user.company_id })
        .where(created_at: month_start..month_end)
        .sum(:amount_cents)
        .to_i
    end

    def sorted_adjustments
      scope = @user.payroll_adjustments.for_month(@payroll_month).includes(:recorded_by)

      case @sort
      when "recorded_by"
        scope.joins(:recorded_by).order(Arel.sql("users.name #{sql_direction}"))
      when "notes"
        scope.order(Arel.sql("payroll_adjustments.notes #{sql_direction} NULLS LAST"))
      else
        scope.order(@sort => @direction, created_at: :desc)
      end
    end

    def sql_direction
      @direction == :asc ? "ASC" : "DESC"
    end

    def with_snapshot(calculated, snapshot)
      recorded = (snapshot.payable_days.to_d + snapshot.bonus_days.to_d + snapshot.penalty_days.to_d).positive?
      Result.new(
        user: calculated.user,
        payroll_month: calculated.payroll_month,
        base_salary_cents: snapshot.base_salary_cents,
        attendance_pay_cents: recorded ? snapshot.attendance_pay_cents : snapshot.base_salary_cents,
        attendance_recorded: recorded,
        payable_days: snapshot.payable_days,
        bonus_days: snapshot.bonus_days,
        penalty_days: snapshot.penalty_days,
        daily_rate_cents: snapshot.daily_rate_cents,
        penalties_cents: snapshot.penalties_cents,
        bonuses_cents: snapshot.bonuses_cents,
        net_pay_cents: snapshot.net_pay_cents,
        advances_cents: snapshot.advances_cents,
        staff_meals_cents: snapshot.staff_meals_cents,
        remaining_pay_cents: snapshot.remaining_pay_cents,
        adjustments: calculated.adjustments,
        advances: calculated.advances,
        finalized: true,
        snapshot: snapshot
      )
    end
  end
end
