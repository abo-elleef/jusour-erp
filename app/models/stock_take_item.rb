# frozen_string_literal: true

class StockTakeItem < ApplicationRecord
  include UnitReferenced

  belongs_to :stock_take
  belongs_to :ingredient
  references_unit :counted_unit, column: :counted_unit_id

  # Counted quantity converted to the ingredient's base unit (counted_unit may
  # be an alternate). Expected quantity is already stored in the base unit.
  def base_counted_quantity
    ingredient.to_base(counted_quantity.to_d, counted_unit)
  rescue ArgumentError
    # Unknown/legacy counted unit — treat the typed count as base so show pages
    # and variance display still render.
    counted_quantity.to_d
  end

  def calculate_variance!
    self.variance = base_counted_quantity - expected_quantity.to_d
  end

  # Location WAC (or fallback). Pass +location_cost+ from a preloaded map to avoid N+1.
  def unit_cost_cents(location_cost: nil)
    return location_cost.to_i unless location_cost.nil?

    Inventory::LocationUnitCost.call(ingredient: ingredient, location: stock_take.location)
  end

  def counted_value_cents(location_cost: nil)
    return nil if counted_quantity.blank?

    (base_counted_quantity * unit_cost_cents(location_cost: location_cost)).round
  end

  def expected_value_cents(location_cost: nil)
    (expected_quantity.to_d * unit_cost_cents(location_cost: location_cost)).round
  end

  def variance_value_cents(location_cost: nil)
    return nil if variance.blank?

    (variance.to_d * unit_cost_cents(location_cost: location_cost)).round
  end
end
