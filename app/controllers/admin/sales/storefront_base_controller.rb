# frozen_string_literal: true

module Admin
  module Sales
    # The public catalog website. Gated on its own `storefront` feature and
    # permission rather than Sales::BaseController's ar_credit_sales/customers:manage
    # — a company could want a catalog without full credit sales (same reasoning
    # as LeadsController).
    class StorefrontBaseController < Admin::BaseController
      before_action { require_feature!(:storefront) }
      before_action :require_storefront_manage

      private

      def require_storefront_manage
        return if current_user.can?("storefront:manage")

        flash[:alert] = t("flash.access_denied")
        redirect_to admin_root_path
      end
    end
  end
end
