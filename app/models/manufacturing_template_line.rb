# frozen_string_literal: true

class ManufacturingTemplateLine < ApplicationRecord
  belongs_to :manufacturing_template
  belongs_to :ingredient

  validates :quantity_used, numericality: { greater_than: 0 }
  validates :ingredient_id, uniqueness: { scope: :manufacturing_template_id }
  validate :ingredient_cannot_be_output

  private

  def ingredient_cannot_be_output
    return if manufacturing_template.blank? || ingredient_id.blank?
    return unless ingredient_id == manufacturing_template.output_ingredient_id

    errors.add(:ingredient_id, :cannot_be_output)
  end
end
