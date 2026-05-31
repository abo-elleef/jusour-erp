# frozen_string_literal: true

class CashDrawerSession < ApplicationRecord
  SHIFTS = %w[morning afternoon evening night].freeze
  STATUSES = %w[open counted reconciled].freeze

  belongs_to :user

  monetize :opening_float_cents
  monetize :expected_cash_cents, allow_nil: true
  monetize :counted_cash_cents, allow_nil: true
  monetize :variance_cents, allow_nil: true

  validates :session_date, :shift, presence: true
  validates :shift, inclusion: { in: SHIFTS }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: %i[session_date shift] }

  scope :open, -> { where(status: "open") }
end
