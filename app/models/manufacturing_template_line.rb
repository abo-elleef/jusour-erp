# frozen_string_literal: true

class ManufacturingTemplateLine < ApplicationRecord
  include UnitReferenced

  belongs_to :manufacturing_template
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :ingredient_id, uniqueness: { scope: :manufacturing_template_id }
  validate :ingredient_cannot_be_output
  validate :unit_valid_for_ingredient

  # quantity_used converted to the input ingredient's base unit.
  def base_quantity_used
    ingredient.to_base(quantity_used, unit)
  rescue ArgumentError
    # Legacy/orphaned unit — treat the stored quantity as base so template
    # show/cost pages still render instead of crashing.
    quantity_used.to_d
  end

  private

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end

  def ingredient_cannot_be_output
    return if manufacturing_template.blank? || ingredient_id.blank?
    return unless ingredient_id == manufacturing_template.output_ingredient_id

    errors.add(:ingredient_id, :cannot_be_output)
  end
end
