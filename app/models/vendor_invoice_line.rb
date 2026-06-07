# frozen_string_literal: true

class VendorInvoiceLine < ApplicationRecord
  belongs_to :vendor_invoice
  belongs_to :ingredient
  has_one :stock_batch, dependent: :nullify

  monetize :unit_price_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }

  def line_total_cents
    (quantity.to_d * unit_price_cents).round
  end
end
