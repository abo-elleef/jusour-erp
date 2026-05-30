# frozen_string_literal: true

class LoyaltyTransaction < ApplicationRecord
  TYPES = %w[earned redeemed adjusted].freeze

  belongs_to :customer
  belongs_to :order, optional: true

  validates :transaction_type, inclusion: { in: TYPES }
  validates :points, presence: true
end
