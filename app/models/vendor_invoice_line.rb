# frozen_string_literal: true

class VendorInvoiceLine < ApplicationRecord
  include UnitReferenced

  belongs_to :vendor_invoice
  belongs_to :ingredient
  references_unit :unit, column: :unit_id
  has_one :stock_batch, dependent: :nullify

  monetize :unit_price_cents
  monetize :line_total_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :line_total_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :derive_unit_price

  # Quantity entered in `unit` (may be an alternate purchase unit) converted to
  # the ingredient's base unit — the unit all stock/costing is stored in.
  def base_quantity
    return quantity.to_d if ingredient.blank?

    ingredient.to_base(quantity, unit)
  end

  # Cost per BASE unit — line total is the source of truth, so this never loses money.
  def base_unit_price_cents
    base = base_quantity
    base.nonzero? ? (line_total_cents.to_d / base).round : 0
  end

  private

  def derive_unit_price
    self.unit_price_cents = quantity.to_d.zero? ? 0 : (line_total_cents.to_d / quantity.to_d).round
  end
end
