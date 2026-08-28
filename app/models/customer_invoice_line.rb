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

  before_validation :apply_product_selling_price
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

  # The unit price is the product's selling price — sales can't set it, so it is
  # enforced here rather than trusted from the form. Only applies while the price
  # is unset/zero, so an existing line keeps the price it was invoiced at.
  def apply_product_selling_price
    return if ingredient.blank?
    return if unit_price_cents.to_i.positive?

    self.unit_price_cents = ingredient.selling_price_cents.to_i
  end

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
