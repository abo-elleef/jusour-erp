# frozen_string_literal: true

class AddOrderTypeToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :order_type, :string, null: false, default: "pickup"
    add_column :orders, :table_number, :string
    add_column :orders, :delivery_address, :text
    add_index :orders, :order_type
  end
end
