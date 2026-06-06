# frozen_string_literal: true

class StaffPayrollController < ApplicationController
  skip_before_action :authenticate_user!

  before_action :set_user
  before_action :require_pin_access!, only: :show

  layout "staff_payroll"

  def show
    @payroll_month = parse_payroll_month
    @payroll_summary = @user.monthly_payroll(@payroll_month)
  end

  def verify
    unless @user.pin_configured?
      flash.now[:alert] = t("staff.payroll_portal.pin_not_set")
      return render :pin, status: :unprocessable_entity
    end

    if @user.authenticate_pin(params[:pin])
      grant_pin_access!
      redirect_to staff_payroll_path(token: @user.payroll_access_token, payroll_month: params[:payroll_month])
    else
      flash.now[:alert] = t("staff.payroll_portal.invalid_pin")
      render :pin, status: :unprocessable_entity
    end
  end

  def lock
    revoke_pin_access!
    redirect_to staff_payroll_path(token: @user.payroll_access_token),
      notice: t("staff.payroll_portal.locked")
  end

  private

  def set_user
    @user = User.active.find_by!(payroll_access_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    raise ActionController::RoutingError, "Not Found"
  end

  def require_pin_access!
    return if pin_access_granted?

    @payroll_month = parse_payroll_month
    render :pin
  end

  def parse_payroll_month
    if params[:payroll_month].present?
      Date.parse("#{params[:payroll_month]}-01")
    else
      Date.current.beginning_of_month
    end
  rescue ArgumentError
    Date.current.beginning_of_month
  end

  def pin_access_granted?
    expires_at = session.dig(:staff_payroll_access, @user.payroll_access_token)
    expires_at.present? && Time.current.to_i < expires_at.to_i
  end

  def grant_pin_access!
    session[:staff_payroll_access] ||= {}
    session[:staff_payroll_access][@user.payroll_access_token] = 8.hours.from_now.to_i
  end

  def revoke_pin_access!
    session[:staff_payroll_access]&.delete(@user.payroll_access_token)
  end
end
