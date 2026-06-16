# frozen_string_literal: true

module PrintAgentCheckout
  extend ActiveSupport::Concern

  private

  def require_print_agent_for_checkout!
    return unless Printing::Config.client_routing?
    return if cookies[:print_agent_healthy] == "1"

    message = t("printing.agent.checkout_blocked")
    respond_to do |format|
      format.html { redirect_to pos_path, alert: message }
      format.json { render json: { error: message, success: false }, status: :service_unavailable }
    end
  end
end
