# frozen_string_literal: true

module SuperAdmin
  class SessionsController < Devise::SessionsController
    layout "super_admin_auth"

    protected

    def after_sign_in_path_for(_resource)
      super_admin_root_path
    end

    def after_sign_out_path_for(_resource)
      new_super_admin_user_session_path
    end
  end
end
