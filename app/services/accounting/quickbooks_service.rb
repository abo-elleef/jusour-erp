# frozen_string_literal: true

module Accounting
  class QuickbooksService
    AUTH_URL = "https://appcenter.intuit.com/connect/oauth2"

    def initialize(integration)
      @integration = integration
    end

    def self.authorization_url(state:)
      client = oauth_client
      client.auth_code.authorize_url(
        redirect_uri: redirect_uri,
        scope: "com.intuit.quickbooks.accounting",
        state: state
      )
    end

    def self.exchange_code(code:)
      client = oauth_client
      token = client.auth_code.get_token(code, redirect_uri: redirect_uri)
      token
    end

    def sync_daily(date)
      return unless @integration.connected?

      pnl = PnlService.new(date, date).call
      post_journal_entry(date, pnl)
      @integration.update!(last_synced_at: Time.current, last_error: nil)
    rescue StandardError => e
      @integration.update!(status: "error", last_error: e.message)
      raise
    end

    private

    def post_journal_entry(date, pnl)
      # QuickBooks Online API journal entry — requires valid OAuth token
      return if @integration.access_token_encrypted.blank?

      HTTParty.post(
        "https://quickbooks.api.intuit.com/v3/company/#{@integration.realm_id}/journalentry",
        headers: {
          "Authorization" => "Bearer #{@integration.access_token_encrypted}",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        },
        body: {
          Line: [
            {
              Description: "Daily sales #{date}",
              Amount: (pnl[:revenue][:net_sales_cents] / 100.0).round(2),
              DetailType: "JournalEntryLineDetail",
              JournalEntryLineDetail: {
                PostingType: "Credit",
                AccountRef: { value: sales_account_code }
              }
            }
          ]
        }.to_json
      )
    end

    def sales_account_code
      @integration.account_mapping["sales_food"] || "4000"
    end

    def self.oauth_client
      OAuth2::Client.new(
        ENV.fetch("QUICKBOOKS_CLIENT_ID", ""),
        ENV.fetch("QUICKBOOKS_CLIENT_SECRET", ""),
        site: "https://appcenter.intuit.com",
        authorize_url: "/connect/oauth2",
        token_url: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
      )
    end

    def self.redirect_uri
      ENV.fetch("QUICKBOOKS_REDIRECT_URI", "")
    end
  end
end
