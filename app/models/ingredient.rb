# frozen_string_literal: true

class Ingredient < ApplicationRecord
  include Tenantable
  include UnitReferenced

  UNITS = %w[kg g lbs oz liters ml pieces packs gallons bales].freeze

  belongs_to :ingredient_category
  # Base unit, referenced by id but exposed as a name (`ingredient.unit`).
  references_unit :unit, column: :unit_id, required: true
  has_many :ingredient_units, dependent: :destroy
  accepts_nested_attributes_for :ingredient_units, allow_destroy: true,
    reject_if: ->(attrs) { attrs["unit_id"].blank? && attrs["base_units_per_unit"].blank? }
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

  before_validation :assign_code, on: :create

  validates :name, presence: true, uniqueness: { scope: :company_id }
  validates :code, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }
  validate :unit_belongs_to_company
  validates :reorder_threshold, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_on_hand, numericality: true
  validates :shelf_life_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :base_unit_locked_when_in_use, on: :update
  before_validation :discard_alternate_units_on_base_change, on: :update

  # Next auto code for an ingredient in `category`: "<CATEGORY_CODE>-NNN", where
  # NNN is the highest existing sequence for that prefix + 1. Custom codes that
  # don't match the "<prefix>-digits" shape are ignored.
  def self.next_code(category)
    prefix = category.code.to_s
    max = unscoped_by_company.where(company_id: category.company_id)
      .where("code ~ ?", "^#{prefix}-[0-9]+$")
      .maximum(Arel.sql("CAST(SUBSTRING(code FROM #{prefix.length + 2}) AS INTEGER)"))
    "#{prefix}-#{((max || 0) + 1).to_s.rjust(3, '0')}"
  end

  scope :active, -> { where(active: true) }
  scope :low_stock, -> { where("quantity_on_hand <= reorder_threshold") }
  scope :out_of_stock, -> { where("quantity_on_hand <= 0") }
  scope :expiring_soon, lambda { |days = StockBatch::EXPIRING_SOON_DAYS|
    where(id: StockBatch.expiring_soon(days).select(:ingredient_id))
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code active quantity_on_hand reorder_threshold ingredient_category_id shelf_life_days]
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

  # The same list as Unit records (base first) — for building id-based dropdowns.
  def available_unit_records
    ([unit_ref] + ingredient_units.map(&:unit_ref)).compact.uniq
  end

  def available_unit_ids
    available_unit_records.map(&:id)
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

  def unit_belongs_to_company
    return if unit_ref.blank? || company.blank?
    return if unit_ref.company_id == company_id

    errors.add(:unit, :not_available)
  end

  # Changing the base unit would silently reinterpret every quantity and cost
  # stored against it (stock on hand, batches). Lock it only while real stock or
  # batch history exists — a fresh ingredient can still be corrected. Alternate
  # units don't block the change; they're cleared instead (see below), since
  # their conversion factors were defined against the old base.
  def base_unit_locked_when_in_use
    return unless unit_id_changed?
    return unless quantity_on_hand.to_d.nonzero? || stock_batches.exists?

    errors.add(:unit, :locked_in_use)
  end

  # When the base unit is (allowably) changed, drop any alternate units: their
  # "N base units per unit" factors are meaningless against the new base and
  # can't be recomputed automatically. The user re-adds them if still needed.
  def discard_alternate_units_on_base_change
    return unless persisted? && unit_id_changed?

    ingredient_units.each(&:mark_for_destruction)
  end

  def assign_code
    self.code = self.class.next_code(ingredient_category) if code.blank? && ingredient_category
  end

  def assign_company
    self.company ||= ingredient_category&.company || Current.company
  end
end
