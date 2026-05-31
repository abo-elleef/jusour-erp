# frozen_string_literal: true

module Pos
  class ManagerPinController < ApplicationController
    layout "pos"

    before_action :require_pos_access!

    def verify
      manager = User.active.where(role: %w[owner manager]).find { |u| u.authenticate_pin(params[:pin]) }

      if manager
        session[:manager_approval] = {
          "action" => params[:action_type],
          "record_id" => params[:record_id],
          "approved_by" => manager.id,
          "expires_at" => 2.minutes.from_now.to_i
        }
        render json: { success: true, manager_name: manager.name }
      else
        render json: { success: false, error: t("flash.pos.invalid_manager_pin") }, status: :unauthorized
      end
    end

    private

    def require_pos_access!
      return if current_user&.can_access_pos?

      head :forbidden
    end
  end
end
