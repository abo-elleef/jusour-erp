# frozen_string_literal: true

class OrderItemModifier < ApplicationRecord
  belongs_to :order_item
  belongs_to :modifier

  monetize :price_adjustment_cents, allow_nil: false
end
