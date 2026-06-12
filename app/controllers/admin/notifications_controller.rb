# frozen_string_literal: true

module Admin
  class NotificationsController < BaseController
    def index
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      @filter = params[:filter].presence_in(%w[all unread inventory accounting]) || "all"
      base = current_user.notifications
      @total_count = base.count
      @unread_count = base.unread.count
      @inventory_count = base.where(notification_type: "inventory").count
      @accounting_count = base.where(notification_type: "accounting").count

      scope = base.order(created_at: :desc)
      scope = scope.unread if @filter == "unread"
      scope = scope.where(notification_type: @filter) if %w[inventory accounting].include?(@filter)
      @notifications = scope.limit(50)
    end

    def mark_read
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      notification = current_user.notifications.find(params[:id])
      notification.mark_as_read!
      redirect_to admin_notifications_path
    end

    def mark_all_read
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      current_user.notifications.unread.update_all(read_at: Time.current)
      redirect_to admin_notifications_path, notice: t("flash.notification.all_read")
    end
  end
end
