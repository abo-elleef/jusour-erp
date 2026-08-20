# frozen_string_literal: true

class StockTransferShipment < ApplicationRecord
  STATUSES = %w[in_transit received voided].freeze

  belongs_to :stock_transfer
  belongs_to :sent_by, class_name: "User"
  belongs_to :received_by, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
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

  def received?
    status == "received"
  end

  def voided?
    status == "voided"
  end
end
