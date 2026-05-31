# frozen_string_literal: true

class AccountingIntegration < ApplicationRecord
  PROVIDERS = %w[quickbooks xero].freeze
  STATUSES = %w[disconnected connected error].freeze

  validates :provider, presence: true, uniqueness: true, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  scope :connected, -> { where(status: "connected") }

  def connected?
    status == "connected" && access_token_encrypted.present?
  end
end
