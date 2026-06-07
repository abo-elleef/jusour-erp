# frozen_string_literal: true

module Admin
  class SettingsController < BaseController
    before_action :authorize_settings

    def index
      @loyalty_redeem_threshold = Setting.get_int("loyalty_redeem_threshold", 100)
      @tax_rates = TaxRate.ordered
    end

    def update
      authorize Setting, :update?, policy_class: SettingPolicy
      if params[:loyalty_redeem_threshold].present?
        Setting.set("loyalty_redeem_threshold", params[:loyalty_redeem_threshold].to_i)
      end
      redirect_to admin_settings_path, notice: t("flash.settings.updated")
    end

    private

    def authorize_settings
      authorize Setting, :index?, policy_class: SettingPolicy
    end
  end
end
