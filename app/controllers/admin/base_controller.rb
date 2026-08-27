# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include PayrollMonthParam

    before_action :require_admin!

    layout "admin"

    private

    def require_admin!
      return if current_user&.admin_access?

      flash[:alert] = t("flash.admin_required")
      redirect_to pos_path
    end

    # Defense-in-depth for feature gating: modules disabled for this company's
    # business profile can't be reached by direct URL even though their nav is
    # hidden. Use as `before_action { require_feature!(:manufacturing) }`.
    def require_feature!(feature)
      return if Current.company&.feature_enabled?(feature)

      flash[:alert] = t("flash.feature_unavailable", default: "That feature isn't available for your business type.")
      redirect_to admin_root_path
    end
  end
end
