# frozen_string_literal: true

class AddVoidFieldsToStockTransferShipments < ActiveRecord::Migration[7.1]
  def change
    add_reference :stock_transfer_shipments, :voided_by, foreign_key: { to_table: :users }, type: :uuid
    add_column :stock_transfer_shipments, :voided_at, :datetime
  end
end
