# frozen_string_literal: true

class Modifier < ApplicationRecord
  belongs_to :modifier_group
  has_many :order_item_modifiers, dependent: :restrict_with_error

  monetize :price_adjustment_cents, allow_nil: false

  validates :name, presence: true
  validates :price_adjustment_cents, numericality: { only_integer: true }
end
