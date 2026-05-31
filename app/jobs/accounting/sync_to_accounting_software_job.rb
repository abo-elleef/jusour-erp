# frozen_string_literal: true

module Accounting
  class SyncToAccountingSoftwareJob < ApplicationJob
    queue_as :low

    def perform(integration_id, date = Date.yesterday)
      integration = AccountingIntegration.find_by(id: integration_id)
      return unless integration&.connected?

      service_class = integration.provider == "quickbooks" ? QuickbooksService : XeroService
      service_class.new(integration).sync_daily(date)
    end
  end
end
