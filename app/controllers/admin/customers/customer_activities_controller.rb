# frozen_string_literal: true

module Admin
  module Customers
    # Rep-logged timeline entries (call/whatsapp/email/meeting/note) on a
    # customer — the twin of Admin::Sales::LeadActivitiesController for after a
    # lead is converted (Bazzar slice F). Only where the distribution sales area
    # exists (Sales::OwnershipScope.applies_to?), so restaurants never see it.
    # Logging needs leads:manage, the permission that logs a lead's activities,
    # so the rep who worked the lead keeps logging once it is a customer.
    class CustomerActivitiesController < Admin::BaseController
      PERMISSION = "leads:manage"

      before_action :require_sales_area
      before_action :require_log_permission
      before_action :set_customer

      def create
        activity = @customer.customer_activities.build(activity_params)
        activity.user = current_user

        if activity.save
          redirect_to admin_customer_path(@customer, tab: "activity"),
            notice: t("customers.activities.logged")
        else
          redirect_to admin_customer_path(@customer, tab: "activity"),
            alert: activity.errors.full_messages.to_sentence
        end
      end

      private

      def require_sales_area
        return if ::Sales::OwnershipScope.applies_to?(Current.company)

        flash[:alert] = t("flash.feature_unavailable", default: "That feature isn't available for your business type.")
        redirect_to admin_root_path
      end

      def require_log_permission
        return if current_user.can?(PERMISSION)

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_customers_path
      end

      # Someone else's customer is a 404 for a limited rep, as on the customer page.
      def set_customer
        @customer = ::Sales::OwnershipScope.for(current_user).customers.find(params[:customer_id])
      end

      def activity_params
        params.require(:customer_activity).permit(:activity_type, :note, :occurred_at)
          .merge(activity_type: params.dig(:customer_activity, :activity_type).to_s
            .presence_in(::CustomerActivity::LOGGABLE_TYPES))
      end
    end
  end
end
