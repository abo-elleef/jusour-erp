# frozen_string_literal: true

# An alternate unit an ingredient can be measured in (e.g. a gallon for an
# ingredient stocked in ml). `base_units_per_unit` is how many of the
# ingredient's base unit one of this unit equals — "1 <unit> = N <base unit>".
class IngredientUnit < ApplicationRecord
  include Tenantable
  include UnitReferenced

  belongs_to :ingredient
  references_unit :unit, column: :unit_id, required: true

  validates :unit_id, uniqueness: { scope: :ingredient_id }
  validates :base_units_per_unit, numericality: { greater_than: 0 }
  validate :unit_differs_from_base
  validate :unit_belongs_to_company

  before_save :clear_other_purchase_units, if: :purchase_unit?

  private

  def clear_other_purchase_units
    ingredient.ingredient_units.where.not(id: id).update_all(purchase_unit: false)
  end

  def unit_differs_from_base
    return if ingredient.blank? || unit_id.blank?
    return unless unit_id == ingredient.unit_id

    errors.add(:unit, :cannot_equal_base_unit)
  end

  def unit_belongs_to_company
    return if unit_ref.blank? || company.blank?
    return if unit_ref.company_id == company_id

    errors.add(:unit, :not_available)
  end
end
