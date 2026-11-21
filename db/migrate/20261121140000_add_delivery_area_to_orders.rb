# frozen_string_literal: true

# The delivery area a POS cashier (or an accepted online request) picked for a
# delivery order. Only a record of the choice: the fee itself is still copied
# onto orders.delivery_fee_cents, so editing or removing an area never changes
# past orders. Nullable, no backfill — older orders simply have no area.
class AddDeliveryAreaToOrders < ActiveRecord::Migration[7.1]
  def change
    add_reference :orders, :delivery_area, type: :uuid, null: true, foreign_key: { on_delete: :nullify }, index: true
  end
end
