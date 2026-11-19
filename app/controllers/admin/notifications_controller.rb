# frozen_string_literal: true

module Admin
  class NotificationsController < BaseController
    # Whitelisted sort keys mapped to their SQL expressions. message_key lives in
    # the jsonb `params` column, so it's sorted/filtered via a ->> extraction.
    SORT_COLUMNS = {
      "time"   => "notifications.created_at",
      "type"   => "notifications.notification_type",
      "alert"  => "notifications.params ->> 'message_key'",
      "status" => "notifications.read_at"
    }.freeze

    def index
      return redirect_to root_path, alert: t("flash.access_denied") unless current_user.admin_access?

      base = current_user.notifications
      @unread_count = base.unread.count

      # Distinct alert keys actually present, for the Alert filter dropdown.
      @alert_keys = base
        .where("notifications.params ->> 'message_key' IS NOT NULL")
        .distinct
        .pluck(Arel.sql("notifications.params ->> 'message_key'"))
        .compact.sort

      @type   = params[:type].presence_in(%w[inventory accounting sales])
      @status = params[:status].presence_in(%w[unread read])
      @alert  = params[:alert].presence_in(@alert_keys)
      @from   = parse_date(params[:from])
      @to     = parse_date(params[:to])
      @sort   = params[:sort].presence_in(SORT_COLUMNS.keys) || "time"
      @dir    = params[:dir] == "asc" ? "asc" : "desc"
      @filtered = @type || @status || @alert || @from || @to

      scope = base
      scope = scope.where(notification_type: @type) if @type
      scope = scope.unread if @status == "unread"
      scope = scope.where.not(read_at: nil) if @status == "read"
      scope = scope.where("notifications.params ->> 'message_key' = ?", @alert) if @alert
      scope = scope.where(created_at: @from.beginning_of_day..) if @from
      scope = scope.where(created_at: ..@to.end_of_day) if @to

      order_sql = Arel.sql("#{SORT_COLUMNS[@sort]} #{@dir} NULLS LAST, notifications.created_at DESC")
      @pagy, @notifications = pagy(:offset, scope.order(order_sql), limit: 50)
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
      Notification.refresh_badge_for(current_user)
      redirect_to admin_notifications_path, notice: t("flash.notification.all_read")
    end

    # "Open" on a live popup: the notification is the user's own, so no admin
    # check here — the page it leads to does its own authorization.
    def open
      notification = current_user.notifications.find(params[:id])
      notification.mark_as_read! if notification.unread?
      redirect_to notification.target_path
    end

    # The bell count as a turbo stream. A tab fetches it when its live
    # connection comes back, to catch up on anything pushed while it was away.
    def badge
      render turbo_stream: turbo_stream.replace(
        ::Notifications::Broadcast::BADGE_ID,
        partial: "admin/notifications/bell_badge",
        locals: { count: current_user.notifications.unread.count }
      )
    end

    private

    def parse_date(raw)
      return if raw.blank?

      Date.parse(raw.to_s)
    rescue ArgumentError
      nil
    end
  end
end
