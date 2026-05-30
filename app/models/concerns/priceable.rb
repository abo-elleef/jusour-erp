# frozen_string_literal: true

module Priceable
  extend ActiveSupport::Concern

  def line_total_cents
    (unit_price_cents + modifier_total_cents) * quantity
  end

  def modifier_total_cents
    0
  end
end
