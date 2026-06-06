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

    def initialize(user, payroll_month)
      @user = user
      @payroll_month = payroll_month.to_date.beginning_of_month
    end

    def call
      adjustments = @user.payroll_adjustments.for_month(@payroll_month).order(created_at: :desc)
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
  end
end
