# frozen_string_literal: true

module Accounting
  class NotifyService
    def self.deliver_to_managers(message:)
      User.where(role: %w[owner manager]).find_each do |user|
        Notification.create!(
          recipient: user,
          notification_type: "accounting",
          params: { message: message }
        )
      end
    end
  end
end
