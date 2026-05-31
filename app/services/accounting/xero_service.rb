# frozen_string_literal: true

module Accounting
  class XeroService
    def initialize(integration)
      @integration = integration
    end

    def self.authorization_url(state:)
      client = oauth_client
      client.auth_code.authorize_url(
        redirect_uri: redirect_uri,
        scope: "accounting.transactions accounting.settings",
        state: state
      )
    end

    def self.exchange_code(code:)
      oauth_client.auth_code.get_token(code, redirect_uri: redirect_uri)
    end

    def sync_daily(date)
      return unless @integration.connected?

      pnl = PnlService.new(date, date).call
      post_manual_journal(date, pnl)
      @integration.update!(last_synced_at: Time.current, last_error: nil)
    rescue StandardError => e
      @integration.update!(status: "error", last_error: e.message)
      raise
    end

    private

    def post_manual_journal(date, pnl)
      return if @integration.access_token_encrypted.blank?

      HTTParty.post(
        "https://api.xero.com/api.xro/2.0/ManualJournals",
        headers: {
          "Authorization" => "Bearer #{@integration.access_token_encrypted}",
          "Content-Type" => "application/json",
          "Xero-tenant-id" => @integration.realm_id
        },
        body: {
          Narration: "POS daily sales #{date}",
          JournalLines: [
            {
              LineAmount: (pnl[:revenue][:net_sales_cents] / 100.0).round(2),
              AccountCode: sales_account_code
            }
          ]
        }.to_json
      )
    end

    def sales_account_code
      @integration.account_mapping["sales_food"] || "200"
    end

    def self.oauth_client
      OAuth2::Client.new(
        ENV.fetch("XERO_CLIENT_ID", ""),
        ENV.fetch("XERO_CLIENT_SECRET", ""),
        site: "https://api.xero.com",
        authorize_url: "https://login.xero.com/identity/connect/authorize",
        token_url: "https://identity.xero.com/connect/token"
      )
    end

    def self.redirect_uri
      ENV.fetch("XERO_REDIRECT_URI", "")
    end
  end
end
