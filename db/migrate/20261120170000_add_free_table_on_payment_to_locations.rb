# frozen_string_literal: true

# Table-service branches: whether a fully paid table order frees its table on its
# own (the default), or the table stays busy until the cashier completes the order.
class AddFreeTableOnPaymentToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :free_table_on_payment, :boolean, default: true, null: false
  end
end
