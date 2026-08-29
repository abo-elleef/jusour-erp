# frozen_string_literal: true

class AddBalanceAfterToStockAdjustments < ActiveRecord::Migration[7.1]
  def change
    add_column :stock_adjustments, :balance_after, :decimal, precision: 10, scale: 3
  end
end
