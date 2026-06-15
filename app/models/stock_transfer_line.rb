# frozen_string_literal: true

class StockTransferLine < ApplicationRecord
  belongs_to :stock_transfer
  belongs_to :ingredient
  has_many :stock_transfer_shipment_lines, dependent: :restrict_with_error

  validates :ingredient_id, uniqueness: { scope: :stock_transfer_id }
  validates :quantity_requested, numericality: { greater_than: 0 }
  validates :quantity_sent, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0 }

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
end
