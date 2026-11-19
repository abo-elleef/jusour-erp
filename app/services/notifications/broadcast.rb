# frozen_string_literal: true

module Notifications
  # Stream names and the two pushes behind live notifications. A user's stream
  # is signed by turbo_stream_from, so nobody can subscribe to another user's.
  module Broadcast
    module_function

    BADGE_ID = "notifications-bell-badge"
    POPUPS_ID = "notification-popups"

    # [user, :notifications, locale] — what both the layout and the job use.
    def stream(user, locale = I18n.locale)
      [user, :notifications, locale.to_s]
    end

    def badge(user)
      count = Notification.unscoped_by_company.where(recipient: user).unread.count
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_replace_to(
          stream(user, locale), target: BADGE_ID,
          partial: "admin/notifications/bell_badge", locals: { count: count }
        )
      end
    end

    # level: "alert" (stays, rings) or "popup" (fades, silent); see Levels.
    def popup(user, notification, level: "alert")
      each_locale do |locale|
        Turbo::StreamsChannel.broadcast_prepend_to(
          stream(user, locale), target: POPUPS_ID,
          partial: "admin/notifications/popup", locals: { notification: notification, level: level }
        )
      end
    end

    def each_locale(&block)
      I18n.available_locales.each { |locale| I18n.with_locale(locale) { block.call(locale) } }
    end
  end
end
