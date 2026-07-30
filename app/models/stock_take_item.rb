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
  end

  def calculate_variance!
    self.variance = base_counted_quantity - expected_quantity.to_d
  end

  # Estimated inventory impact using the ingredient's current unit cost.
  # Safe with eager-loaded ingredients — no extra queries.
  def variance_value_cents
    return nil if variance.blank?

    (variance.to_d * ingredient.cost_per_unit_cents.to_i).round
  end
end
