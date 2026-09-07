# frozen_string_literal: true

# Stores a user-confirmed inventory value (in cents) for a given date and company.
# Used by the P&L to supply opening and closing stock values for the trading account.
class InventorySnapshot < ApplicationRecord
  include Tenantable

  monetize :value_cents

  validates :snapshot_date, presence: true
  validates :value_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :snapshot_date, uniqueness: { scope: :company_id }

  scope :on_or_before, ->(date) { where(snapshot_date: ..date).order(snapshot_date: :desc) }

  def self.find_or_build_for(date, company: Current.company)
    where(company_id: company.id, snapshot_date: date).first_or_initialize
  end
end
