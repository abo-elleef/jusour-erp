# frozen_string_literal: true

class AddCountedUnitToStockTakeItems < ActiveRecord::Migration[7.1]
  def change
    # Unit the count was entered in. Null means the ingredient's base unit.
    add_column :stock_take_items, :counted_unit, :string
  end
end
