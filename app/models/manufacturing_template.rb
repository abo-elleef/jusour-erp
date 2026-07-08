# frozen_string_literal: true

class ManufacturingTemplate < ApplicationRecord
  include Tenantable

  belongs_to :output_ingredient, class_name: "Ingredient"
  has_many :manufacturing_template_lines, dependent: :destroy
  has_many :input_ingredients, through: :manufacturing_template_lines, source: :ingredient
  has_many :manufacturing_runs, dependent: :restrict_with_error

  accepts_nested_attributes_for :manufacturing_template_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :yield_quantity, numericality: { greater_than: 0 }
  validate :must_have_input_lines, if: :active?
  validate :yield_unit_valid_for_output

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # yield_quantity converted to the output ingredient's base unit.
  def base_yield_quantity
    output_ingredient.to_base(yield_quantity, yield_unit)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active position]
  end

  private

  def must_have_input_lines
    return if manufacturing_template_lines.any?

    errors.add(:base, :needs_input_lines)
  end

  def yield_unit_valid_for_output
    return if yield_unit.blank? || output_ingredient.blank?
    return if output_ingredient.available_units.include?(yield_unit)

    errors.add(:yield_unit, :invalid)
  end
end
