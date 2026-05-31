# frozen_string_literal: true

class StockTakeItem < ApplicationRecord
  belongs_to :stock_take
  belongs_to :ingredient

  def calculate_variance!
    self.variance = counted_quantity.to_d - expected_quantity.to_d
  end
end
