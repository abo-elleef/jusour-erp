# frozen_string_literal: true

class ManufacturingTemplateLine < ApplicationRecord
  belongs_to :manufacturing_template
  belongs_to :ingredient

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :ingredient_id, uniqueness: { scope: :manufacturing_template_id }
  validate :ingredient_cannot_be_output
  validate :unit_valid_for_ingredient

  # quantity_used converted to the input ingredient's base unit.
  def base_quantity_used
    ingredient.to_base(quantity_used, unit)
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
