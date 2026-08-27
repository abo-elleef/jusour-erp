# frozen_string_literal: true

class CustomerInvoiceLine < ApplicationRecord
  include UnitReferenced
  include MoneyInputs

  belongs_to :customer_invoice
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  monetize :unit_price_cents
  monetize :line_total_cents
  money_input :unit_price_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :unit_valid_for_ingredient

  before_validation :derive_line_total

  scope :ordered, -> { order(:position, :created_at) }

  # Quantity sold, converted to the ingredient's base stock unit (the unit stock
  # and costing are kept in). Falls back to the raw quantity for legacy units.
  def base_quantity
    return quantity.to_d if ingredient.blank?

    ingredient.to_base(quantity, unit)
  rescue ArgumentError
    quantity.to_d
  end

  private

  # Unit price (firm, after any tier/override discount the seller applied) is the
  # source of truth; the line total follows from it.
  def derive_line_total
    self.line_total_cents = (quantity.to_d * unit_price_cents.to_i).round
  end

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
