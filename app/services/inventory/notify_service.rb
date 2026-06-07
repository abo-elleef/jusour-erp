# frozen_string_literal: true

module Inventory
  class NotifyService
    def self.deliver_to_managers(message_key:, message_params: {}, ingredient: nil)
      User.where(role: %w[owner manager]).find_each do |user|
        Notification.create!(
          recipient: user,
          notification_type: "inventory",
          params: {
            message_key: message_key,
            message_params: message_params.deep_stringify_keys,
            ingredient_id: ingredient&.id
          }
        )
      end
    end
  end
end
