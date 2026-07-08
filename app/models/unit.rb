# frozen_string_literal: true

# A measurement unit available to a company. A default set is seeded on company
# creation (marked `system` as provenance only); companies can add their own on
# top. Built-in and custom units are otherwise identical — both can be renamed
# or deleted (deletion is blocked only while the unit is referenced).
class Unit < ApplicationRecord
  include Tenantable

  # Built-in units seeded for every company.
  DEFAULTS = %w[kg g lbs oz liters ml pieces packs gallons bales].freeze

  validates :name, presence: true, uniqueness: { scope: :company_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # Ingredients that use this unit as their base unit or as an alternate unit.
  def ingredients_using
    scoped = Ingredient.unscoped_by_company.where(company_id: company_id)
    alt_ids = IngredientUnit.unscoped_by_company.where(company_id: company_id, unit_id: id).select(:ingredient_id)
    scoped.where(unit_id: id).or(scoped.where(id: alt_ids))
  end

  # True when any record — an ingredient, recipe, transfer, count, adjustment,
  # invoice line or template — still references this unit by id (an FK would
  # otherwise block deletion).
  def in_use?
    return true if ingredients_using.exists?

    Recipe.where(unit_id: id).exists? ||
      ManufacturingTemplateLine.where(unit_id: id).exists? ||
      ManufacturingTemplate.unscoped_by_company.where(yield_unit_id: id).exists? ||
      StockTransferLine.where(unit_id: id).exists? ||
      StockTakeItem.where(counted_unit_id: id).exists? ||
      StockAdjustment.where(unit_id: id).exists? ||
      VendorInvoiceLine.where(unit_id: id).exists?
  end

  # Any unit that isn't referenced anywhere can be deleted (built-in and custom
  # units are treated identically — `system` is seed provenance only).
  def deletable?
    !in_use?
  end

  # Seed the built-in units for a company (idempotent).
  def self.seed_defaults!(company)
    DEFAULTS.each_with_index do |name, i|
      company.units.where("LOWER(name) = ?", name).first ||
        company.units.create!(name: name, system: true, active: true, position: i)
    end
  end
end
