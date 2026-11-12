# frozen_string_literal: true

# A placed order is locked: its items change only after someone types the branch's
# edit-orders PIN. The PIN is one per branch, shared by whoever runs the floor.
class AddPlaceOrderEditLock < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :edit_orders_pin_digest, :string
    add_column :locations, :edit_orders_pin_failed_attempts, :integer, null: false, default: 0
    add_column :locations, :edit_orders_pin_locked_until, :datetime

    # Set while a placed order is open in the register for changes; cleared when it
    # is placed again. edit_count > 0 puts an EDITED banner on the kitchen tickets.
    add_column :orders, :unlocked_for_edit_at, :datetime
    add_reference :orders, :unlocked_for_edit_by, type: :uuid, foreign_key: { to_table: :users }, null: true
    add_column :orders, :edit_count, :integer, null: false, default: 0
  end
end
