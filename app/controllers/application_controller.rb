# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Locale
  include Pundit::Authorization
  include Pagy::Method

  before_action :authenticate_user!, unless: :devise_controller?
  before_action :set_current_company, if: :user_signed_in?
  before_action :enforce_subscription!, if: :user_signed_in?, unless: :devise_controller?
  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def set_current_company
    Current.company = current_user.company
  end

  # Lock out companies we switched off or whose subscription ran past its grace
  # period. Signed-in users land on a plain explanation page (with sign-out)
  # rather than a broken screen. A super admin impersonating a company bypasses
  # the lock so they can still help a customer who is locked out.
  def enforce_subscription!
    company = Current.company
    return if company.nil? || session[:impersonating]
    return unless company.access_blocked?

    respond_to do |format|
      format.html { redirect_to subscription_locked_path }
      format.any  { head :payment_required }
    end
  end

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
        render turbo_stream: turbo_stream.append(
          "toast-container",
          partial: "shared/toast",
          locals: { message: flash.now[:alert], type: :alert }
        ), status: :forbidden
      end
    end
  end

  def default_path_for_role
    return new_user_session_path unless user_signed_in?

    after_sign_in_path_for(current_user)
  end

  def after_sign_in_path_for(resource)
    return root_path if resource.nil?

    if resource.can_access_admin?
      admin_root_path
    elsif resource.can_access_pos?
      pos_path
    elsif resource.can_access_kds?
      kitchen_path
    else
      root_path
    end
  end

  def authenticate_manager_pin!(action_type:, record_id: nil)
    pin = params[:pin].presence || session.dig(:manager_approval, "pin")
    manager = User.active.where(role: %w[owner manager], company_id: Current.company&.id)
      .find { |u| u.authenticate_pin(pin) }

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
