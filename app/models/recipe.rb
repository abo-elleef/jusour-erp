# frozen_string_literal: true

class Recipe < ApplicationRecord
  include UnitReferenced

  belongs_to :menu_item
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :menu_item_id, uniqueness: { scope: :ingredient_id }
  validate :unit_valid_for_ingredient

  # quantity_used expressed in the ingredient's base unit (unit may be an alternate).
  def base_quantity_used
    ingredient.to_base(quantity_used, unit)
  end

  private

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
