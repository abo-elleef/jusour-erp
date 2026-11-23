# frozen_string_literal: true

# Pickup orders can be made to carry a customer (per branch). The cashier types
# the customer's phone or skips with a reason; the reason is kept on the order so
# the capture rate can be reported honestly.
class AddPickupCustomerCapture < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :pickup_customer_prompt, :boolean, default: false, null: false
    add_column :orders, :customer_skip_reason, :string
  end
end
