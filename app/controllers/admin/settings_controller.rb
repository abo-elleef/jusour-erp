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
      @receipt_logo = Current.company.company_setting&.receipt_logo
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
      if (params[:receipt_logo].present? || params[:remove_receipt_logo].present?) && !update_receipt_logo
        return redirect_to admin_settings_path, alert: @logo_error
      end

      redirect_to admin_settings_path, notice: t("flash.settings.updated")
    end

    private

    # Returns false (with the error message in @logo_error) when the upload is rejected.
    def update_receipt_logo
      setting = CompanySetting.current_or_initialize
      setting.receipt_logo = params[:receipt_logo] if params[:receipt_logo].present?
      setting.remove_receipt_logo = params[:remove_receipt_logo]
      return true if setting.save

      @logo_error = setting.errors.full_messages.to_sentence
      false
    end

    def authorize_settings
      authorize Setting, :index?, policy_class: SettingPolicy
    end
  end
end
