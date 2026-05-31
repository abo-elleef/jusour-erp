# frozen_string_literal: true

module Admin
  module Accounting
    class IntegrationsController < BaseController
      before_action :set_integration, only: %i[sync disconnect]

      def index
        AccountingIntegration::PROVIDERS.each do |provider|
          AccountingIntegration.find_or_create_by!(provider: provider) do |i|
            i.status = "disconnected"
          end
        end
        @integrations = AccountingIntegration.order(:provider)
      end

      def connect
        provider = params[:provider]
        unless AccountingIntegration::PROVIDERS.include?(provider)
          return redirect_to admin_accounting_integrations_path, alert: t("flash.accounting.unknown_provider")
        end

        state = SecureRandom.hex(16)
        session[:oauth_state] = state
        session[:oauth_provider] = provider

        url = if provider == "quickbooks"
                ::Accounting::QuickbooksService.authorization_url(state: state)
              else
                ::Accounting::XeroService.authorization_url(state: state)
              end

        if url.blank? || ENV["#{provider.upcase}_CLIENT_ID"].blank?
          redirect_to admin_accounting_integrations_path,
            alert: t("flash.accounting.oauth_credentials", provider: provider.titleize)
          return
        end

        redirect_to url, allow_other_host: true
      end

      def callback
        if params[:state] != session.delete(:oauth_state)
          return redirect_to admin_accounting_integrations_path, alert: t("flash.accounting.invalid_oauth_state")
        end

        provider = session.delete(:oauth_provider) || params[:provider]
        integration = AccountingIntegration.find_by!(provider: provider)

        token = if provider == "quickbooks"
                  ::Accounting::QuickbooksService.exchange_code(code: params[:code])
                else
                  ::Accounting::XeroService.exchange_code(code: params[:code])
                end

        integration.update!(
          status: "connected",
          access_token_encrypted: token.token,
          refresh_token_encrypted: token.refresh_token,
          token_expires_at: token.expires_at ? Time.at(token.expires_at) : nil,
          realm_id: params[:realmId] || params[:realm_id],
          last_error: nil
        )

        redirect_to admin_accounting_integrations_path, notice: t("flash.accounting.provider_connected", provider: provider.titleize)
      rescue StandardError => e
        redirect_to admin_accounting_integrations_path, alert: t("flash.accounting.connection_failed", message: e.message)
      end

      def sync
        ::Accounting::SyncToAccountingSoftwareJob.perform_later(@integration.id, Date.yesterday)
        redirect_to admin_accounting_integrations_path, notice: t("flash.accounting.sync_queued")
      end

      def disconnect
        @integration.update!(
          status: "disconnected",
          access_token_encrypted: nil,
          refresh_token_encrypted: nil,
          token_expires_at: nil
        )
        redirect_to admin_accounting_integrations_path, notice: t("flash.accounting.disconnected")
      end

      private

      def set_integration
        @integration = AccountingIntegration.find(params[:id])
      end
    end
  end
end
