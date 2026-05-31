# frozen_string_literal: true

class PurchaseOrderItem < ApplicationRecord
  STATUSES = %w[pending partial received discrepancy].freeze

  belongs_to :purchase_order
  belongs_to :ingredient

  monetize :unit_price_cents

  validates :quantity_ordered, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  def remaining_to_receive
    [quantity_ordered.to_d - quantity_received.to_d, 0].max
  end
end
