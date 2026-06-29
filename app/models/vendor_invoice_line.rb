# frozen_string_literal: true

class VendorInvoiceLine < ApplicationRecord
  belongs_to :vendor_invoice
  belongs_to :ingredient
  has_one :stock_batch, dependent: :nullify

  monetize :unit_price_cents
  monetize :line_total_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :line_total_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :derive_unit_price

  private

  def derive_unit_price
    self.unit_price_cents = quantity.to_d.zero? ? 0 : (line_total_cents.to_d / quantity.to_d).round
  end
end
