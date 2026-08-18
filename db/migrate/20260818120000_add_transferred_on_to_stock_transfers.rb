# frozen_string_literal: true

class AddTransferredOnToStockTransfers < ActiveRecord::Migration[7.1]
  def up
    add_column :stock_transfers, :transferred_on, :date
    execute <<~SQL.squish
      UPDATE stock_transfers
      SET transferred_on = COALESCE((requested_at AT TIME ZONE 'UTC')::date, CURRENT_DATE)
      WHERE transferred_on IS NULL
    SQL
    change_column_null :stock_transfers, :transferred_on, false
    add_index :stock_transfers, :transferred_on
  end

  def down
    remove_index :stock_transfers, :transferred_on
    remove_column :stock_transfers, :transferred_on
  end
end
