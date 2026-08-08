# frozen_string_literal: true

class StockTransferTemplateLine < ApplicationRecord
  include UnitReferenced

  belongs_to :stock_transfer_template, inverse_of: :stock_transfer_template_lines
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  validates :ingredient_id, uniqueness: { scope: :stock_transfer_template_id }
  validates :default_quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :unit_valid_for_ingredient

  before_validation :assign_default_unit

  scope :ordered, -> { order(:position, :created_at) }

  private

  def assign_default_unit
    return if unit.present? || ingredient.blank?

    self.unit = ingredient.unit
  end

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
