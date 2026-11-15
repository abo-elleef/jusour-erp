# frozen_string_literal: true

# A customer's self-order from the public menu, waiting for a cashier to accept
# or reject it. It only becomes a real Order on accept, so spam never burns order
# numbers, stock or drawer cash. `cart` is what the customer asked for; `quote`
# is the server-side price snapshot shown back to them.
class CreateOnlineOrderRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :online_order_requests, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.references :location, type: :uuid, null: false, foreign_key: true
      t.references :customer, type: :uuid, foreign_key: true
      t.references :delivery_area, type: :uuid, foreign_key: true
      t.references :order, type: :uuid, foreign_key: true, index: { unique: true }
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.string :token, null: false
      t.string :fulfillment, null: false
      t.string :customer_name, null: false
      t.string :phone, null: false
      t.text :address
      t.text :note
      t.jsonb :cart, null: false, default: []
      t.jsonb :quote, null: false, default: {}
      t.integer :total_cents, null: false, default: 0
      t.integer :delivery_fee_cents, null: false, default: 0
      t.string :ip
      t.string :user_agent
      t.string :reject_reason
      t.datetime :decided_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :online_order_requests, :token, unique: true
    add_index :online_order_requests, %i[location_id status created_at]
    add_index :online_order_requests, %i[company_id phone created_at]
    add_index :online_order_requests, %i[company_id ip created_at]
  end
end
