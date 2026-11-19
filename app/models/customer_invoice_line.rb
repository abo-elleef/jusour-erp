# frozen_string_literal: true

class CustomerInvoiceLine < ApplicationRecord
  include UnitReferenced
  include MoneyInputs
  include WholeSalesQuantity

  belongs_to :customer_invoice
  belongs_to :ingredient
  references_unit :unit, column: :unit_id

  monetize :unit_price_cents
  monetize :line_total_cents
  money_input :unit_price_cents

  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :unit_valid_for_ingredient

  before_validation :apply_product_selling_price
  before_validation :record_list_price
  before_validation :derive_line_total

  scope :ordered, -> { order(:position, :created_at) }

  # Quantity sold, converted to the ingredient's base stock unit (the unit stock
  # and costing are kept in). Falls back to the raw quantity for legacy units.
  def base_quantity
    return quantity.to_d if ingredient.blank?

    ingredient.to_base(quantity, unit)
  rescue ArgumentError
    quantity.to_d
  end

  # The product's standard cost (Ingredient#cost_per_unit_cents, per base unit)
  # for one of this line's units; nil when the product has no cost set, so no
  # warning is ever raised against a blank or zero cost.
  def unit_cost_cents
    return if ingredient.blank?

    cost = ingredient.cost_per_unit_cents.to_i
    return unless cost.positive?

    factor = ingredient.base_units_per(unit) || 1
    (cost * factor).round
  end

  # A warning, not a rule: the sale still saves and confirms.
  def below_cost?
    cost = unit_cost_cents
    cost.present? && unit_price_cents.to_i < cost
  end

  private

  def sales_document = customer_invoice

  # A blank (or zero) price falls back to the product's selling price — the
  # same starting value the form fills on product select. Sales may type any
  # other price; record_list_price marks it as changed.
  def apply_product_selling_price
    return if ingredient.blank?
    return if unit_price_cents.to_i.positive?

    self.unit_price_cents = ingredient.selling_price_cents.to_i
  end

  # The auto-filled price is captured when the line is created or its product
  # changes. Lines from before this existed keep a NULL list price and are
  # never flagged, so old and imported invoices don't suddenly read as edited.
  def record_list_price
    return if ingredient.blank?
    # Imported history carries the old system's prices; nothing was overridden here.
    return if customer_invoice&.historical?

    self.list_price_cents = ingredient.selling_price_cents.to_i if new_record? || ingredient_id_changed?
    self.price_overridden = list_price_cents.present? && unit_price_cents.to_i != list_price_cents
  end

  # Unit price (firm, after any tier/override discount the seller applied) is the
  # source of truth; the line total follows from it.
  def derive_line_total
    self.line_total_cents = (quantity.to_d * unit_price_cents.to_i).round
  end

  def unit_valid_for_ingredient
    return if unit.blank? || ingredient.blank?
    return if ingredient.available_units.include?(unit)

    errors.add(:unit, :invalid)
  end
end
