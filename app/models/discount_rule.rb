# frozen_string_literal: true

class DiscountRule < ApplicationRecord
  include Tenantable
  include MoneyInputs

  money_input :minimum_order_cents

  DISCOUNT_TYPES = %w[percentage fixed_amount].freeze
  APPLIES_TO = %w[order item category].freeze

  has_many :order_discounts, dependent: :nullify

  validates :name, :discount_type, :discount_value, :applies_to, presence: true
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }
  validates :applies_to, inclusion: { in: APPLIES_TO }
  validates :code, uniqueness: { scope: :company_id }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :valid_now, -> {
    active.where("expires_at IS NULL OR expires_at > ?", Time.current)
      .where("uses_remaining IS NULL OR uses_remaining > 0")
  }

  def usable?
    active? && (expires_at.nil? || expires_at > Time.current) &&
      (uses_remaining.nil? || uses_remaining.positive?)
  end
end
