# frozen_string_literal: true

module Accounting
  class MonthlyPayrollService
    Result = Struct.new(
      :user,
      :payroll_month,
      :base_salary_cents,
      :daily_rate_cents,
      :penalties_cents,
      :bonuses_cents,
      :net_pay_cents,
      :adjustments,
      keyword_init: true
    )

    def initialize(user, payroll_month, sort: nil, direction: nil)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
      @sort = PayrollAdjustment::SORTABLE_COLUMNS.include?(sort.to_s) ? sort.to_s : PayrollAdjustment::DEFAULT_SORT
      @direction = direction.to_s == "asc" ? :asc : :desc
    end

    def call
      adjustments = sorted_adjustments
      base = @user.monthly_salary_cents.to_i
      penalties = adjustments.penalties.sum(:amount_cents)
      bonuses = adjustments.bonuses.sum(:amount_cents)

      Result.new(
        user: @user,
        payroll_month: @payroll_month,
        base_salary_cents: base,
        daily_rate_cents: @user.daily_rate_cents,
        penalties_cents: penalties,
        bonuses_cents: bonuses,
        net_pay_cents: base - penalties + bonuses,
        adjustments: adjustments
      )
    end

    def self.for_all_staff(payroll_month)
      User.active.order(:name).filter_map do |user|
        next if user.monthly_salary_cents.to_i.zero? &&
                user.payroll_adjustments.for_month(payroll_month).none?

        new(user, payroll_month).call
      end
    end

    private

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
  end
end
