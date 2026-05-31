# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Locale
  include Pundit::Authorization
  include Pagy::Method

  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[name role])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name role])
  end

  def user_not_authorized
    respond_to do |format|
      format.html do
        flash[:alert] = t("flash.unauthorized")
        redirect_back(fallback_location: default_path_for_role)
      end
      format.json { render json: { error: t("flash.unauthorized") }, status: :forbidden }
      format.turbo_stream do
        flash.now[:alert] = t("flash.unauthorized")
        render turbo_stream: turbo_stream.update("flash-messages", partial: "shared/flash_alert"),
               status: :forbidden
      end
    end
  end

  def default_path_for_role
    return new_user_session_path unless user_signed_in?

    after_sign_in_path_for(current_user)
  end

  def after_sign_in_path_for(resource)
    return root_path if resource.nil?

    if resource.kitchen?
      kitchen_path
    elsif resource.can_access_admin?
      admin_root_path
    elsif resource.can_access_pos?
      pos_path
    else
      root_path
    end
  end

  def authenticate_manager_pin!(action_type:, record_id: nil)
    pin = params[:pin].presence || session.dig(:manager_approval, "pin")
    manager = User.active.where(role: %w[owner manager]).find { |u| u.authenticate_pin(pin) }

    unless manager
      return false
    end

    session[:manager_approval] = {
      "action" => action_type,
      "record_id" => record_id,
      "approved_by" => manager.id,
      "expires_at" => 2.minutes.from_now.to_i
    }
    true
  end

  def manager_approval_valid?(action_type:, record_id: nil)
    data = session[:manager_approval]
    return false unless data

    return false if Time.current.to_i > data["expires_at"].to_i
    return false unless data["action"] == action_type
    return false if record_id.present? && data["record_id"].to_s != record_id.to_s

    true
  end

  def clear_manager_approval!
    session.delete(:manager_approval)
  end
end
