# frozen_string_literal: true

module Admin
  class SettingsController < BaseController
    before_action :authorize_settings

    def index
      @loyalty_redeem_threshold = Setting.get_int("loyalty_redeem_threshold", 100)
      @print_routing = Setting.get("print_routing", Printing::Config::ROUTING_CLIENT)
      @print_agent_port = Setting.get_int("print_agent_port", Printing::Config::DEFAULT_AGENT_PORT)
      @print_agent_token = Setting.get("print_agent_token", "")
      @receipt_footer_text = Printing::Config.receipt_footer_text
      @restrict_stock_transfers_to_source = Setting.restrict_stock_transfers_to_source?
      @tax_rates = TaxRate.ordered
    end

    def update
      authorize Setting, :update?, policy_class: SettingPolicy
      if params[:loyalty_redeem_threshold].present?
        Setting.set("loyalty_redeem_threshold", params[:loyalty_redeem_threshold].to_i)
      end
      if params[:print_routing].present?
        Setting.set("print_routing", params[:print_routing])
      end
      if params[:print_agent_port].present?
        Setting.set("print_agent_port", params[:print_agent_port].to_i)
      end
      if params.key?(:restrict_stock_transfers_to_source)
        Setting.set("restrict_stock_transfers_to_source", params[:restrict_stock_transfers_to_source])
      end
      Setting.set("print_agent_token", params[:print_agent_token].to_s) if params.key?(:print_agent_token)
      Setting.set("receipt_footer_text", params[:receipt_footer_text].to_s.strip) if params.key?(:receipt_footer_text)
      redirect_to admin_settings_path, notice: t("flash.settings.updated")
    end

    private

    def authorize_settings
      authorize Setting, :index?, policy_class: SettingPolicy
    end
  end
end
