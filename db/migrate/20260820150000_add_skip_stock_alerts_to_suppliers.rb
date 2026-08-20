# frozen_string_literal: true

class AddSkipStockAlertsToSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :suppliers, :skip_stock_alerts, :boolean, default: false, null: false
  end
end
