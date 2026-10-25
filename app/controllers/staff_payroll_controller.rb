# frozen_string_literal: true

class StaffPayrollController < ApplicationController
  include PayrollMonthParam

  skip_before_action :authenticate_user!

  before_action :set_user
  before_action :require_pin_access!, only: :show

  layout "staff_payroll"

  def show
    @payroll_month = parse_payroll_month
    @payroll_summary = @user.monthly_payroll(@payroll_month)
  end

  def verify
    @payroll_month = parse_payroll_month

    unless @user.pin_configured?
      flash.now[:alert] = t("staff.payroll_portal.pin_not_set")
      return render :pin, status: :unprocessable_entity
    end

    if @user.payroll_pin_locked?
      flash.now[:alert] = t("staff.payroll_portal.pin_locked", minutes: minutes_until_unlock)
      return render :pin, status: :too_many_requests
    end

    if @user.verify_payroll_pin(params[:pin])
      grant_pin_access!
      redirect_to staff_payroll_path(token: @user.payroll_access_token, payroll_month: params[:payroll_month])
    elsif @user.payroll_pin_locked?
      flash.now[:alert] = t("staff.payroll_portal.pin_locked", minutes: minutes_until_unlock)
      render :pin, status: :too_many_requests
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
    @user = User.unscoped.active.find_by!(payroll_access_token: params[:token])
    Current.company = @user.company
  rescue ActiveRecord::RecordNotFound
    raise ActionController::RoutingError, "Not Found"
  end

  def require_pin_access!
    return if pin_access_granted?

    @payroll_month = parse_payroll_month
    render :pin
  end

  def pin_access_granted?
    prune_expired_pin_access!
    session.dig(:staff_payroll_access, @user.payroll_access_token).present?
  end

  def grant_pin_access!
    prune_expired_pin_access!
    session[:staff_payroll_access] ||= {}
    session[:staff_payroll_access][@user.payroll_access_token] = 8.hours.from_now.to_i
  end

  # One entry per payroll link unlocked on this device, each good for 8 hours.
  # Drop the expired ones so a shared device's session cookie doesn't keep
  # growing with every link ever opened on it.
  def prune_expired_pin_access!
    access = session[:staff_payroll_access]
    return if access.blank?

    now = Time.current.to_i
    access.delete_if { |_token, expires_at| expires_at.to_i <= now }
    session.delete(:staff_payroll_access) if access.empty?
  end

  def minutes_until_unlock
    [((@user.payroll_pin_locked_until - Time.current) / 60.0).ceil, 1].max
  end

  def revoke_pin_access!
    session[:staff_payroll_access]&.delete(@user.payroll_access_token)
  end
end
