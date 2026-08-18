# frozen_string_literal: true

class AddCountFieldsToStockTransferLines < ActiveRecord::Migration[7.1]
  def change
    add_column :stock_transfer_lines, :order_limit, :decimal, precision: 10, scale: 3
    add_column :stock_transfer_lines, :counted_quantity, :decimal, precision: 10, scale: 3
  end
end
