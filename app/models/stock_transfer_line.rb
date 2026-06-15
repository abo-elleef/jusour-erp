# frozen_string_literal: true

class StockTransferLine < ApplicationRecord
  belongs_to :stock_transfer
  belongs_to :ingredient

  validates :ingredient_id, uniqueness: { scope: :stock_transfer_id }
  validates :quantity_requested, numericality: { greater_than: 0 }
  validates :quantity_sent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  def available_at_source
    il = stock_transfer.from_location.ingredient_stock(ingredient)
    il&.quantity_on_hand.to_d
  end
end
