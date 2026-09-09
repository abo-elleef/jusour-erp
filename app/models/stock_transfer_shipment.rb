# frozen_string_literal: true

class StockTransferShipment < ApplicationRecord
  # voided: cancelled while still travelling, so no stock ever moved.
  # reverted: was received, and the stock has been moved back to the source.
  STATUSES = %w[in_transit received voided reverted].freeze

  belongs_to :stock_transfer
  belongs_to :sent_by, class_name: "User"
  belongs_to :received_by, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
  belongs_to :reverted_by, class_name: "User", optional: true
  has_many :stock_transfer_shipment_lines, dependent: :destroy
  has_many :stock_transfer_lines, through: :stock_transfer_shipment_lines

  validates :sequence, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :sent_at, presence: true

  scope :ordered, -> { order(:sequence) }
  scope :in_transit, -> { where(status: "in_transit") }
  scope :received, -> { where(status: "received") }

  def in_transit?
    status == "in_transit"
  end

  def reverted?
    status == "reverted"
  end

  # Only a received shipment can be reverted; one still travelling is voided
  # instead, which moves no stock because sending never moved any.
  def can_revert?
    status == "received"
  end

  # Lines where less arrived than left. Sending moves no stock, so the difference is
  # goods that never made it — worth showing rather than silently folding back into
  # the sender's outstanding amount.
  def short_lines
    stock_transfer_shipment_lines.select do |line|
      line.quantity_received.to_d < line.quantity_sent.to_d
    end
  end

  def short?
    received? && short_lines.any?
  end

  # The receiver counts what actually arrived and is trusted over the dispatch note,
  # so a shipment can arrive with MORE than was recorded as sent.
  def surplus_lines
    stock_transfer_shipment_lines.select do |line|
      line.quantity_received.to_d > line.quantity_sent.to_d
    end
  end

  def surplus?
    received? && surplus_lines.any?
  end

  def received?
    status == "received"
  end

  def voided?
    status == "voided"
  end
end
