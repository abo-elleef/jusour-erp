# frozen_string_literal: true

class ModifierRecipe < ApplicationRecord
  include Tenantable
  include UnitReferenced

  belongs_to :modifier
  belongs_to :ingredient
  # Optional, like an item recipe's: blank means the ingredient's base unit.
  references_unit :unit, column: :unit_id

  validates :quantity, numericality: { other_than: 0 }
  validates :modifier_id, uniqueness: { scope: :ingredient_id }
  validate :unit_valid_for_ingredient

  # quantity in the ingredient's base unit (the recipe's unit may be an alternate,
  # e.g. 1 piece of an ingredient stocked by the 20-piece batch). Signed.
  def base_quantity
    ingredient.to_base(quantity, unit)
  rescue ArgumentError
    # The unit is no longer one of the ingredient's units: read the stored
    # quantity as base, as Recipe#base_quantity_used does.
    quantity.to_d
  end

  private

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
