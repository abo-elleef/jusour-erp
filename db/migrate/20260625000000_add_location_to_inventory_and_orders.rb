# frozen_string_literal: true

class AddLocationToInventoryAndOrders < ActiveRecord::Migration[7.1]
  def change
    add_reference :stock_batches, :location, foreign_key: true, type: :uuid
    add_reference :stock_adjustments, :location, foreign_key: true, type: :uuid
    add_reference :stock_takes, :location, foreign_key: true, type: :uuid
    add_reference :manufacturing_runs, :location, foreign_key: true, type: :uuid
    add_reference :orders, :location, foreign_key: true, type: :uuid
  end
end
