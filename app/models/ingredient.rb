# frozen_string_literal: true

class Ingredient < ApplicationRecord
  include Tenantable

  UNITS = %w[kg g lbs oz liters ml pieces packs gallons bales].freeze

  belongs_to :ingredient_category
  has_many :ingredient_units, dependent: :destroy
  accepts_nested_attributes_for :ingredient_units, allow_destroy: true,
    reject_if: ->(attrs) { attrs["unit"].blank? && attrs["base_units_per_unit"].blank? }
  has_many :ingredient_locations, dependent: :destroy
  has_many :locations, through: :ingredient_locations
  has_many :recipes, dependent: :destroy
  has_many :menu_items, through: :recipes
  has_many :stock_adjustments, dependent: :nullify
  has_many :stock_batches, dependent: :nullify
  has_many :supplier_ingredients, dependent: :destroy
  has_many :suppliers, through: :supplier_ingredients
  has_many :supplier_price_histories, dependent: :nullify
  has_many :stock_take_items, dependent: :nullify
  has_many :manufacturing_template_lines, dependent: :restrict_with_error
  has_many :output_manufacturing_templates, class_name: "ManufacturingTemplate",
    foreign_key: :output_ingredient_id, dependent: :restrict_with_error, inverse_of: :output_ingredient

  monetize :cost_per_unit_cents

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :unit, presence: true, inclusion: { in: UNITS }
  validates :reorder_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_on_hand, numericality: true
  validates :shelf_life_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :base_unit_locked_when_in_use, on: :update

  scope :active, -> { where(active: true) }
  scope :low_stock, -> { where("quantity_on_hand <= reorder_threshold") }
  scope :out_of_stock, -> { where("quantity_on_hand <= 0") }
  scope :expiring_soon, lambda { |days = StockBatch::EXPIRING_SOON_DAYS|
    where(id: StockBatch.expiring_soon(days).select(:ingredient_id))
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name unit active quantity_on_hand reorder_threshold ingredient_category_id shelf_life_days]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[ingredient_category]
  end

  def low_stock?
    quantity_on_hand <= reorder_threshold
  end

  def out_of_stock?
    quantity_on_hand <= 0
  end

  def near_low_stock?
    return false if reorder_threshold.zero?

    quantity_on_hand <= reorder_threshold * 1.2 && !low_stock?
  end

  def stock_status
    return :out if out_of_stock?
    return :low if low_stock?
    return :near if near_low_stock?

    :ok
  end

  def stock_value_cents
    (quantity_on_hand.to_d * cost_per_unit_cents).round
  end

  # All units this ingredient can be measured in: its base unit plus any
  # configured alternate units. The base unit is always first.
  def available_units
    [unit] + ingredient_units.map(&:unit).reject { |u| u == unit }
  end

  # How many base units one of `for_unit` equals. The base unit is factor 1.
  def base_units_per(for_unit)
    return 1.to_d if for_unit.blank? || for_unit == unit

    row = ingredient_units.detect { |iu| iu.unit == for_unit }
    row&.base_units_per_unit&.to_d
  end

  # Convert a quantity entered in `from_unit` into the base unit.
  def to_base(quantity, from_unit)
    factor = base_units_per(from_unit)
    raise ArgumentError, "Unknown unit #{from_unit.inspect} for #{name}" if factor.nil?

    quantity.to_d * factor
  end

  # Convert a base-unit quantity into `to_unit` for display.
  def from_base(quantity, to_unit)
    factor = base_units_per(to_unit)
    raise ArgumentError, "Unknown unit #{to_unit.inspect} for #{name}" if factor.nil?

    quantity.to_d / factor
  end

  private

  # Changing the base unit would silently reinterpret every stored quantity
  # (stock on hand, batches, recipes). Lock it once the ingredient is in use.
  def base_unit_locked_when_in_use
    return unless unit_changed?
    return unless quantity_on_hand.to_d.nonzero? || stock_batches.exists? || ingredient_units.exists?

    errors.add(:unit, :locked_in_use)
  end

  def assign_company
    self.company ||= ingredient_category&.company || Current.company
  end
end
