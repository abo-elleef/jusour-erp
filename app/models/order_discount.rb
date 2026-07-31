# frozen_string_literal: true

class OrderDiscount < ApplicationRecord
  belongs_to :order
  belongs_to :discount_rule, optional: true
  belongs_to :menu_promo, optional: true
  belongs_to :order_item, optional: true

  monetize :amount_cents

  validates :description, :amount_cents, presence: true

  scope :promos, -> { where.not(menu_promo_id: nil) }
end
