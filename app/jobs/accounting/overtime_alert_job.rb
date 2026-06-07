# frozen_string_literal: true

module Accounting
  class OvertimeAlertJob < ApplicationJob
    queue_as :default

    def perform
      Company.find_each do |company|
        with_company(company) do
          User.where(role: %w[cashier manager]).find_each do |user|
            checker = OvertimeCheckService.new(user)
            next unless checker.over_overtime? && checker.rule

            NotifyService.deliver_to_managers(
              message_key: "overtime_weekly",
              message_params: {
                name: user.name,
                hours: checker.weekly_hours.round(1),
                threshold: checker.rule.weekly_threshold_hours
              }
            )
          end
        end
      end
    end
  end
end
