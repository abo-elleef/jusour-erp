# frozen_string_literal: true

class StockTransferShipmentLine < ApplicationRecord
  belongs_to :stock_transfer_shipment
  belongs_to :stock_transfer_line

  delegate :ingredient, to: :stock_transfer_line

  validates :stock_transfer_line_id, uniqueness: { scope: :stock_transfer_shipment_id }
  validates :quantity_sent, numericality: { greater_than: 0 }
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
