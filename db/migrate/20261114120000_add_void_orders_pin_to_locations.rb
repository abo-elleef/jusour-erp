# frozen_string_literal: true

# A second branch PIN, six digits, that lets the register void an order. Kept apart
# from the edit-orders PIN so a branch can hand out "change items" without
# handing out "make the sale disappear".
class AddVoidOrdersPinToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :void_orders_pin_digest, :string
    add_column :locations, :void_orders_pin_failed_attempts, :integer, null: false, default: 0
    add_column :locations, :void_orders_pin_locked_until, :datetime
  end
end
