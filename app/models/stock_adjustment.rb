# frozen_string_literal: true

class StockAdjustment < ApplicationRecord
  belongs_to :ingredient
  belongs_to :user
  belongs_to :stock_batch, optional: true

  ADJUSTMENT_TYPES = %w[
    delivery vendor_invoice manual_add manual_remove
    waste_spoilage waste_prep waste_overproduction
    cycle_count_correction consumption
    production_consumption production_output
  ].freeze

  validates :quantity_delta, numericality: true
  validate :quantity_delta_not_zero
  validates :adjustment_type, inclusion: { in: ADJUSTMENT_TYPES }

  after_create :update_ingredient_stock

  private

  def quantity_delta_not_zero
    return unless quantity_delta.to_d.zero?

    errors.add(:quantity_delta, "must not be zero")
  end

  def update_ingredient_stock
    new_qty = ingredient.quantity_on_hand.to_d + quantity_delta.to_d
    ingredient.update_columns(quantity_on_hand: new_qty)
  end
end
