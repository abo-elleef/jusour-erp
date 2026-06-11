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
        adjustments: adjustments,
        finalized: false,
        snapshot: nil
      )
    end

    def self.for_all_staff(payroll_month)
      snapshots = PayrollSnapshot.for_month(payroll_month).index_by(&:user_id)

      User.active.order(:name).filter_map do |user|
        next unless payroll_row?(user, payroll_month, snapshots[user.id])

        new(user, payroll_month).call
      end
    end

    def self.payroll_row?(user, payroll_month, snapshot)
      return true if snapshot

      user.monthly_salary_cents.to_i.positive? ||
        user.payroll_adjustments.for_month(payroll_month).exists?
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

    def with_snapshot(calculated, snapshot)
      Result.new(
        user: calculated.user,
        payroll_month: calculated.payroll_month,
        base_salary_cents: snapshot.base_salary_cents,
        daily_rate_cents: snapshot.daily_rate_cents,
        penalties_cents: snapshot.penalties_cents,
        bonuses_cents: snapshot.bonuses_cents,
        net_pay_cents: snapshot.net_pay_cents,
        adjustments: calculated.adjustments,
        finalized: true,
        snapshot: snapshot
      )
    end
  end
end
