# frozen_string_literal: true

class ManufacturingTemplate < ApplicationRecord
  belongs_to :output_ingredient, class_name: "Ingredient"
  has_many :manufacturing_template_lines, dependent: :destroy
  has_many :input_ingredients, through: :manufacturing_template_lines, source: :ingredient
  has_many :manufacturing_runs, dependent: :restrict_with_error

  accepts_nested_attributes_for :manufacturing_template_lines,
    allow_destroy: true,
    reject_if: proc { |attrs| attrs["ingredient_id"].blank? }

  validates :name, presence: true, uniqueness: true
  validates :yield_quantity, numericality: { greater_than: 0 }
  validate :must_have_input_lines, if: :active?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name active position]
  end

  private

  def must_have_input_lines
    return if manufacturing_template_lines.any?

    errors.add(:base, :needs_input_lines)
  end
end
