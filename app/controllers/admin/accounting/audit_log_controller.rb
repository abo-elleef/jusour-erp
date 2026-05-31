# frozen_string_literal: true

module Admin
  module Accounting
    class AuditLogController < BaseController
      before_action :owner_only!

      def index
        @q = AuditLogEntry.ransack(params[:q])
        @actions = AuditLogEntry.distinct.order(:action).pluck(:action)
        @users = User.where(id: AuditLogEntry.select(:user_id).distinct).order(:name)
        @filtered = params[:q].present? && params[:q].to_unsafe_h.values.any?(&:present?)
        @pagy, @entries = pagy(:offset, @q.result.includes(:user).order(created_at: :desc), limit: 50)
      end

      private

      def owner_only!
        return if current_user.owner?

        redirect_to admin_root_path, alert: t("flash.accounting.owner_only")
      end
    end
  end
end
