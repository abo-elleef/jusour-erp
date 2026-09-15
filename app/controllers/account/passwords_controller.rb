# frozen_string_literal: true

module Account
  # Lets any signed-in user change their own password. The admin staff form can
  # also set a password, but it lives behind `admin_access?` and the owner /
  # accountant-only staff index — cashiers and kitchen staff have no way in.
  class PasswordsController < ApplicationController
    layout "devise"

    before_action :set_user
    before_action :set_back_path

    def edit; end

    def update
      if password_blank?
        @user.errors.add(:password, :blank)
        return render :edit, status: :unprocessable_entity
      end

      # `update_with_password` verifies :current_password and adds the
      # :invalid / :blank error itself, so a wrong current password never saves.
      if @user.update_with_password(password_params)
        # Changing the password rotates the authenticatable salt, which would
        # otherwise sign the user out of their own session.
        bypass_sign_in(@user)
        redirect_to @back_path, notice: t("flash.account.password_updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = current_user
    end

    # `after_sign_in_path_for` is private on ApplicationController, and the page
    # is reached from three different layouts, so resolve the return path here.
    def set_back_path
      @back_path = after_sign_in_path_for(current_user)
    end

    def password_params
      params.require(:user).permit(:current_password, :password, :password_confirmation)
    end

    def password_blank?
      params.dig(:user, :password).blank?
    end
  end
end
