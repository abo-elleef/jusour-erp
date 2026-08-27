# frozen_string_literal: true

class CreditNoteLine < ApplicationRecord
  include UnitReferenced
  include MoneyInputs

  belongs_to :credit_note
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  monetize :unit_price_cents
  monetize :line_total_cents
  money_input :unit_price_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }

  before_validation :derive_line_total

  scope :ordered, -> { order(:position, :created_at) }

  # Returned quantity in the ingredient's base stock unit.
  def base_quantity
    return quantity.to_d if ingredient.blank?

    ingredient.to_base(quantity, unit)
  rescue ArgumentError
    quantity.to_d
  end

  private

  def derive_line_total
    self.line_total_cents = (quantity.to_d * unit_price_cents.to_i).round
  end
end
