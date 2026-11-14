# frozen_string_literal: true

# A delivery invoice now has its own shipping track beside the payment status:
#   waiting_for_shipping → shipped (handed to the courier; = dispatched_at)
#   → shipping_completed (someone checked the courier's system: delivered).
# Pickup invoices have no track (NULL).
#
# Backfill is raw SQL (no app models in migrations): confirmed delivery
# invoices that were already dispatched are "shipped", the rest are waiting.
# None are marked completed — nobody has confirmed those deliveries here yet.
class AddShippingStatusToCustomerInvoices < ActiveRecord::Migration[7.1]
  def up
    add_column :customer_invoices, :shipping_status, :string
    add_column :customer_invoices, :shipping_completed_at, :datetime
    add_reference :customer_invoices, :shipping_completed_by, type: :uuid, foreign_key: { to_table: :users }
    add_index :customer_invoices, %i[company_id shipping_status]

    execute <<~SQL.squish
      UPDATE customer_invoices
      SET shipping_status = CASE WHEN dispatched_at IS NOT NULL THEN 'shipped' ELSE 'waiting_for_shipping' END
      WHERE status = 'confirmed' AND fulfillment_method = 'delivery'
    SQL
  end

  def down
    remove_index :customer_invoices, %i[company_id shipping_status]
    remove_reference :customer_invoices, :shipping_completed_by, foreign_key: { to_table: :users }
    remove_column :customer_invoices, :shipping_completed_at
    remove_column :customer_invoices, :shipping_status
  end
end
