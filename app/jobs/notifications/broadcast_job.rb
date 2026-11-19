# frozen_string_literal: true

module Notifications
  # Pushes a notification to its recipient's open admin tabs, so it pops up
  # without a page reload (the same idea as the online-order badge on the POS).
  #
  # popup: true  — a new notification: refresh the bell count and show a card.
  # popup: false — read state changed (mark read / mark all read): refresh the
  #                bell count only, so every open tab drops the badge together.
  #
  # The UI language is per browser session, not per user, so each tab listens on
  # a stream that carries its locale (see Notifications::Broadcast.stream) and
  # this job renders once per available locale.
  class BroadcastJob < ApplicationJob
    queue_as :default

    def perform(user_id, notification_id = nil, popup: false)
      user = User.unscoped_by_company.find_by(id: user_id)
      return if user.nil?

      notification = Notification.unscoped_by_company.find_by(id: notification_id) if notification_id
      return if popup && (notification.nil? || !notification.unread?)

      Current.set(company: user.company) do
        Broadcast.badge(user)
        Broadcast.popup(user, notification) if popup
      end
    end
  end
end
