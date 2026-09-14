# frozen_string_literal: true

class VendorCreditNoteLine < ApplicationRecord
  include UnitReferenced
  include MoneyInputs

  belongs_to :vendor_credit_note
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  monetize :unit_price_cents
  monetize :line_total_cents
  # The line total is what the supplier credited, so it is what gets typed. Unit
  # price is derived from it — the other way round, rounding the per-unit figure
  # would lose fractions of a pound off the credited total.
  money_input :line_total_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :line_total_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :derive_unit_price

  scope :ordered, -> { order(:position, :created_at) }

  def base_quantity
    return quantity.to_d if ingredient.blank?

    ingredient.to_base(quantity, unit)
  rescue ArgumentError
    quantity.to_d
  end

  private

  def derive_unit_price
    self.unit_price_cents = quantity.to_d.zero? ? 0 : (line_total_cents.to_d / quantity.to_d).round
  end
end
