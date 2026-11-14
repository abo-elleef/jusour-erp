# frozen_string_literal: true

# Where an order came from: the register (pos), the offline register synced later
# (offline), or a customer's self-order from the public menu (online). Existing
# rows default to pos; offline ones are not back-filled (client_uuid marks them).
class AddSourceToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :source, :string, null: false, default: "pos"
  end
end
