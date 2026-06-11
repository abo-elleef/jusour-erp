# frozen_string_literal: true

class StockBatch < ApplicationRecord
  EXPIRING_SOON_DAYS = 2

  belongs_to :ingredient
  belongs_to :location, optional: true
  belongs_to :supplier, optional: true
  belongs_to :vendor_invoice_line, optional: true
  has_many :stock_adjustments, dependent: :nullify

  scope :fifo_order, -> { order(received_on: :asc, created_at: :asc) }
  scope :with_stock, -> { where("quantity_remaining > 0") }
  scope :expiring_soon, lambda { |days = EXPIRING_SOON_DAYS|
    where("expires_on IS NOT NULL AND expires_on <= ?", Date.current + days.days)
      .where("quantity_remaining > 0")
  }

  def expired?
    expires_on.present? && expires_on < Date.current
  end
end
