# frozen_string_literal: true

module SuperAdmin
  class BaseController < ApplicationController
    skip_before_action :authenticate_user!
    skip_before_action :set_current_company
    skip_before_action :enforce_subscription!

    before_action :authenticate_super_admin_user!

    layout "super_admin"

    private

    def authenticate_super_admin_user!
      return if super_admin_user_signed_in?

      redirect_to new_super_admin_user_session_path, alert: "Please sign in as super admin."
    end
  end
end
