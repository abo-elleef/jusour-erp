# frozen_string_literal: true

class Ingredient < ApplicationRecord
  include Tenantable

  UNITS = %w[kg g lbs oz liters ml pieces packs].freeze

  belongs_to :ingredient_category
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

  scope :active, -> { where(active: true) }
  scope :low_stock, -> { where("quantity_on_hand <= reorder_threshold") }
  scope :out_of_stock, -> { where("quantity_on_hand <= 0") }
  scope :expiring_soon, lambda { |days = StockBatch::EXPIRING_SOON_DAYS|
    where(id: StockBatch.expiring_soon(days).select(:ingredient_id))
  }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name unit active quantity_on_hand reorder_threshold ingredient_category_id]
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

  private

  def assign_company
    self.company ||= ingredient_category&.company || Current.company
  end
end
