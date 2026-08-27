# frozen_string_literal: true

module Admin
  module Sales
    # Distribution sales area — only available when the company's profile enables
    # credit sales, and only to users who can manage customers.
    class BaseController < Admin::BaseController
      before_action { require_feature!(:ar_credit_sales) }
      before_action :require_sales_access

      private

      def require_sales_access
        return if current_user.can?("customers:manage")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_root_path
      end
    end
  end
end
