# frozen_string_literal: true

# An alternate unit an ingredient can be measured in (e.g. a gallon for an
# ingredient stocked in ml). `base_units_per_unit` is how many of the
# ingredient's base unit one of this unit equals — "1 <unit> = N <base unit>".
class IngredientUnit < ApplicationRecord
  include Tenantable

  belongs_to :ingredient

  validates :unit, presence: true, inclusion: { in: Ingredient::UNITS }
  validates :unit, uniqueness: { scope: :ingredient_id }
  validates :base_units_per_unit, numericality: { greater_than: 0 }
  validate :unit_differs_from_base

  private

  def unit_differs_from_base
    return if ingredient.blank? || unit.blank?
    return unless unit == ingredient.unit

    errors.add(:unit, :cannot_equal_base_unit)
  end
end
