# frozen_string_literal: true

class OrderDiscount < ApplicationRecord
  belongs_to :order
  belongs_to :discount_rule, optional: true

  monetize :amount_cents

  validates :description, :amount_cents, presence: true
end
