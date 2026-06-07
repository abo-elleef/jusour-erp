# frozen_string_literal: true

module Accounting
  class NotifyService
    def self.deliver_to_managers(message_key:, message_params: {})
      User.where(role: %w[owner manager]).find_each do |user|
        Notification.create!(
          recipient: user,
          company: user.company,
          notification_type: "accounting",
          params: {
            message_key: message_key,
            message_params: message_params.deep_stringify_keys
          }
        )
      end
    end
  end
end
