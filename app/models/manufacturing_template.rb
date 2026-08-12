# frozen_string_literal: true

class ManufacturingTemplate < ApplicationRecord
  include Tenantable
  include UnitReferenced

  CONTROL_MODES = %w[runs main_ingredient].freeze

  belongs_to :output_ingredient, class_name: "Ingredient"
  belongs_to :main_ingredient, class_name: "Ingredient", optional: true
  references_unit :yield_unit, column: :yield_unit_id
  has_many :manufacturing_template_lines, dependent: :destroy
  has_many :input_ingredients, through: :manufacturing_template_lines, source: :ingredient
  has_many :manufacturing_runs, dependent: :restrict_with_error

  accepts_nested_attributes_for :manufacturing_template_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :yield_quantity, numericality: { greater_than: 0 }
  validates :control_mode, inclusion: { in: CONTROL_MODES }
  validate :must_have_input_lines, if: :active?
  validate :yield_unit_valid_for_output
  validate :main_ingredient_is_an_input_line, if: :main_ingredient_controlled?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # A run's size is driven by the actual amount of one designated input ("main
  # ingredient") rather than by an explicit run count. The recipe lines still
  # hold the ratios; the entered main amount just derives the multiplier.
  def main_ingredient_controlled?
    control_mode == "main_ingredient"
  end

  # The input line that corresponds to the main ingredient (the one metered
  # against real received stock). nil unless configured.
  def main_line
    return nil if main_ingredient_id.blank?

    manufacturing_template_lines.detect { |line| line.ingredient_id == main_ingredient_id }
  end

  # yield_quantity converted to the output ingredient's base unit.
  def base_yield_quantity
    output_ingredient.to_base(yield_quantity, yield_unit)
  rescue ArgumentError
    # Legacy/orphaned yield unit — treat the stored quantity as base so template
    # show/cost pages still render instead of crashing.
    yield_quantity.to_d
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active position]
  end

  private

  def must_have_input_lines
    return if manufacturing_template_lines.any?

    errors.add(:base, :needs_input_lines)
  end

  # The main ingredient must be one of the recipe's own input lines — that's the
  # line whose per-batch quantity gives the ratio the entered amount scales against.
  def main_ingredient_is_an_input_line
    if main_ingredient_id.blank?
      errors.add(:main_ingredient_id, :blank)
    elsif manufacturing_template_lines.reject(&:marked_for_destruction?).none? { |line| line.ingredient_id == main_ingredient_id }
      errors.add(:main_ingredient_id, :not_an_input)
    end
  end

  def yield_unit_valid_for_output
    return if yield_unit.blank? || output_ingredient.blank?
    return if output_ingredient.available_units.include?(yield_unit)

    errors.add(:yield_unit, :invalid)
  end
end
