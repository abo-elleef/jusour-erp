# frozen_string_literal: true

class StockTransferLine < ApplicationRecord
  belongs_to :stock_transfer
  belongs_to :ingredient
  has_many :stock_transfer_shipment_lines, dependent: :restrict_with_error

  # Requested quantity as typed in `unit`; converted to base on the way in so the
  # transfer engine only ever sees base-unit quantities.
  attr_accessor :quantity_requested_input

  validates :ingredient_id, uniqueness: { scope: :stock_transfer_id }
  validates :quantity_requested, numericality: { greater_than: 0 }
  validates :quantity_sent, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0 }
  validate :unit_valid_for_ingredient

  before_validation :convert_requested_input

  # Show a base-unit quantity in this line's (fixed) unit.
  def in_line_unit(base_quantity)
    ingredient.from_base(base_quantity.to_d, unit)
  end

  # Convert a quantity typed in this line's unit back to the base unit.
  def to_base_unit(quantity)
    ingredient.to_base(quantity.to_d, unit)
  end

  def available_at_source
    il = stock_transfer.from_location.ingredient_stock(ingredient)
    il&.quantity_on_hand.to_d
  end

  def available_batches_at_source
    ingredient.stock_batches
      .where(location: stock_transfer.from_location)
      .with_stock
      .sum(:quantity_remaining).to_d
  end

  def transferable_quantity_at_source
    [available_at_source, available_batches_at_source].min
  end

  def quantity_pending_send
    [quantity_requested.to_d - quantity_sent.to_d, 0].max
  end

  def quantity_in_transit
    [quantity_sent.to_d - quantity_received.to_d, 0].max
  end

  def quantity_remaining_to_receive
    quantity_in_transit
  end

  def fulfilled?
    quantity_received.to_d >= quantity_requested.to_d
  end

  private

  def convert_requested_input
    return if quantity_requested_input.blank?

    self.quantity_requested = ingredient.to_base(quantity_requested_input, unit)
  end

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
