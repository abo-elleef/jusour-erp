# frozen_string_literal: true

class AddSupplierToStockTakes < ActiveRecord::Migration[7.1]
  def change
    add_reference :stock_takes, :supplier, type: :uuid, foreign_key: true, index: true
  end
end
