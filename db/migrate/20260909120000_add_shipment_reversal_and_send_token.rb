# frozen_string_literal: true

class AddShipmentReversalAndSendToken < ActiveRecord::Migration[7.1]
  def change
    # Reverting a *received* shipment moves stock back to the source, so it needs
    # the same audit trail as voiding an in-transit one, plus a reason: a
    # correction that moves real stock must record why.
    add_column :stock_transfer_shipments, :reverted_at, :datetime
    add_column :stock_transfer_shipments, :reverted_reason, :text
    add_reference :stock_transfer_shipments, :reverted_by, type: :uuid,
      foreign_key: { to_table: :users }, null: true

    # Idempotency for the send form. A double click posts the same token twice;
    # the second insert loses to this index and is treated as already done.
    # Deliberately not a content hash — sending the same lines twice on purpose
    # is legitimate here, so only the form submission itself can be deduplicated.
    add_column :stock_transfer_shipments, :send_token, :string
    add_index :stock_transfer_shipments, :send_token, unique: true
  end
end
