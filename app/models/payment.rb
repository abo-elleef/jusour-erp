# frozen_string_literal: true

class Payment < ApplicationRecord
  METHODS = %w[cash card apple_pay google_pay gift_card].freeze
  STATUSES = %w[pending completed failed refunded partially_refunded].freeze

  belongs_to :order
  belongs_to :processed_by_user, class_name: "User", optional: true

  monetize :amount_cents
  monetize :tip_cents, allow_nil: false
  monetize :refunded_amount_cents, allow_nil: false

  validates :payment_method, inclusion: { in: METHODS }
  validates :status, inclusion: { in: STATUSES }
end
