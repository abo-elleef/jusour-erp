# frozen_string_literal: true

module Accounting
  class OvertimeCheckService
    def initialize(user, week_start = Date.current.beginning_of_week)
      @user = user
      @week_start = week_start
      @rule = OvertimeRule.active.first
    end

    attr_reader :rule

    def weekly_hours
      week_end = @week_start + 6.days
      ShiftLog.completed
        .where(user: @user)
        .where(clocked_in_at: @week_start.beginning_of_day..week_end.end_of_day)
        .sum(&:hours_worked)
    end

    def approaching_overtime?
      return false unless @rule

      weekly_hours >= (@rule.weekly_threshold_hours - 2)
    end

    def over_overtime?
      return false unless @rule

      weekly_hours > @rule.weekly_threshold_hours
    end
  end
end
