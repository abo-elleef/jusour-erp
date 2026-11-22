# frozen_string_literal: true

# Call-center orders: staff in a room away from the branches (phone, WhatsApp)
# send orders to a branch as requests; a cashier there accepts them, so the order
# is that cashier's and prints on the branch's printers.
#
#   channel        — "public" (customer self-order) or "call_center" (staff typed it)
#   created_by_id  — the call-center agent who sent it
#   expires_at     — now optional: a call-center request never expires on its own
#                    (the customer was already told yes); the branch is nudged instead.
#   locations.call_center_enabled — the branch takes call-center orders, separate
#                    from the public-menu online ordering switch.
class AddCallCenterToOnlineOrderRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :online_order_requests, :channel, :string, null: false, default: "public"
    add_reference :online_order_requests, :created_by, type: :uuid, foreign_key: { to_table: :users }, index: false
    add_index :online_order_requests, %i[company_id created_by_id created_at]
    change_column_null :online_order_requests, :expires_at, true

    add_column :locations, :call_center_enabled, :boolean, null: false, default: false
  end
end
