# frozen_string_literal: true

class CombinationRecipeLine < ApplicationRecord
  include Tenantable
  include UnitReferenced

  belongs_to :combination_recipe
  belongs_to :ingredient
  # Optional, like an item recipe's: blank means the ingredient's base unit.
  references_unit :unit, column: :unit_id

  validates :quantity, numericality: { greater_than: 0 }
  validates :ingredient_id, uniqueness: { scope: :combination_recipe_id }
  validate :unit_valid_for_ingredient

  # quantity in the ingredient's base unit (the unit may be an alternate).
  def base_quantity
    ingredient.to_base(quantity, unit)
  rescue ArgumentError
    # A unit the ingredient no longer has reads as base, as Recipe does.
    quantity.to_d
  end

  private

  def assign_company
    self.company ||= combination_recipe&.company || Current.company
  end

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
