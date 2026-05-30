# frozen_string_literal: true

class GiftCard < ApplicationRecord
  monetize :balance_cents

  validates :code, presence: true, uniqueness: true
  validates :balance_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def redeem!(amount_cents)
    raise "Insufficient balance" if balance_cents < amount_cents

    update!(balance_cents: balance_cents - amount_cents)
  end
end
