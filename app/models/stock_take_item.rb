# frozen_string_literal: true

class StockTakeItem < ApplicationRecord
  belongs_to :stock_take
  belongs_to :ingredient

  # Counted quantity converted to the ingredient's base unit (counted_unit may
  # be an alternate). Expected quantity is already stored in the base unit.
  def base_counted_quantity
    ingredient.to_base(counted_quantity.to_d, counted_unit)
  end

  def calculate_variance!
    self.variance = base_counted_quantity - expected_quantity.to_d
  end
end
