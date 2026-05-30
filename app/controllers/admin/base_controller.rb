# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :require_admin!

    layout "admin"

    private

    def require_admin!
      return if current_user&.admin_access?

      flash[:alert] = "Admin access required."
      redirect_to pos_path
    end
  end
end
