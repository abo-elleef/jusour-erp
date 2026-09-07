# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include PayrollMonthParam
    include FeatureGated

    before_action :require_admin!

    layout "admin"

    private

    def require_admin!
      return if current_user&.admin_access?

      flash[:alert] = t("flash.admin_required")
      redirect_to pos_path
    end
  end
end
