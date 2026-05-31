# frozen_string_literal: true

module Accounting
  class OvertimeAlertJob < ApplicationJob
    queue_as :default

    def perform
      User.where(role: %w[cashier manager]).find_each do |user|
        checker = OvertimeCheckService.new(user)
        next unless checker.over_overtime? && checker.rule

        NotifyService.deliver_to_managers(
          message: "#{user.name} has exceeded #{checker.weekly_hours.round(1)} hours this week " \
                   "(OT threshold: #{checker.rule.weekly_threshold_hours}h)."
        )
      end
    end
  end
end
