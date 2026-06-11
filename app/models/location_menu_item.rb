# frozen_string_literal: true

class LocationMenuItem < ApplicationRecord
  belongs_to :location
  belongs_to :menu_item

  monetize :price_override_cents, allow_nil: true

  validates :menu_item_id, uniqueness: { scope: :location_id }

  scope :available, -> { where(available: true) }

  def effective_price_cents
    price_override_cents.presence || menu_item.base_price_cents
  end
end
