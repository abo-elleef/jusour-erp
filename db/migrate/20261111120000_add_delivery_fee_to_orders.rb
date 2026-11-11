# frozen_string_literal: true

# What the customer pays for delivery on a POS delivery order. Restaurant delivery
# fees vary too much to price in advance (distance, driver, time of day), so the
# cashier types it in when collecting payment. It is part of the order total and
# is recognised as sales revenue with the day's takings.
class AddDeliveryFeeToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :delivery_fee_cents, :integer, default: 0, null: false
  end
end
