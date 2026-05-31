# frozen_string_literal: true

module Admin
  class NotificationsController < BaseController
    def index
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      @notifications = current_user.notifications.order(created_at: :desc).limit(50)
    end

    def mark_read
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      notification = current_user.notifications.find(params[:id])
      notification.mark_as_read!
      redirect_to admin_notifications_path
    end

    def mark_all_read
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      current_user.notifications.unread.mark_as_read!
      redirect_to admin_notifications_path, notice: t("flash.notification.all_read")
    end
  end
end
