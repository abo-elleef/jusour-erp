# frozen_string_literal: true

class AddUnitToStockTransferLines < ActiveRecord::Migration[7.1]
  def change
    # Unit chosen at request time, fixed for the whole request→ship→receive
    # lifecycle. Null means the ingredient's base unit. Quantities are still
    # stored in the base unit; this is used only for entry/display.
    add_column :stock_transfer_lines, :unit, :string
  end
end
