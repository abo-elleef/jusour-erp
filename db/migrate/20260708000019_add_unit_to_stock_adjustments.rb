# frozen_string_literal: true

class AddUnitToStockAdjustments < ActiveRecord::Migration[7.1]
  def change
    # Unit a manual adjustment was entered in (display only; quantity_delta is
    # always stored in the ingredient's base unit). Null = base unit / system.
    add_column :stock_adjustments, :unit, :string
  end
end
