# frozen_string_literal: true

# Orders get their daily number when they are placed (or paid), not when the
# first item goes into the cart. A draft has no number; placed_at records the
# moment it was committed so the kitchen can queue by it.
#
# Raw SQL on purpose: migrations must not depend on app models.
class NumberOrdersOnPlacement < ActiveRecord::Migration[7.1]
  def up
    change_column_null :orders, :order_number, true
    add_column :orders, :placed_at, :datetime
    add_index :orders, %i[location_id placed_at]

    execute <<~SQL.squish
      UPDATE orders SET placed_at = COALESCE(kitchen_sent_at, created_at)
      WHERE status <> 'draft'
    SQL

    # Open drafts give their number back and take a fresh one when placed.
    execute "UPDATE orders SET order_number = NULL WHERE status = 'draft'"
  end

  def down
    execute <<~SQL.squish
      UPDATE orders SET order_number = 'D-' || LEFT(id::text, 8)
      WHERE order_number IS NULL
    SQL
    remove_index :orders, %i[location_id placed_at]
    remove_column :orders, :placed_at
    change_column_null :orders, :order_number, false
  end
end
