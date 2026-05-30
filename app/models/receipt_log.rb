# frozen_string_literal: true

class ReceiptLog < ApplicationRecord
  belongs_to :order

  DELIVERY_METHODS = %w[email sms].freeze
  STATUSES = %w[sent failed].freeze

  validates :delivery_method, inclusion: { in: DELIVERY_METHODS }
  validates :status, inclusion: { in: STATUSES }
end
