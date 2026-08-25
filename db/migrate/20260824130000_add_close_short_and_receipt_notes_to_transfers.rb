# frozen_string_literal: true

# Two gaps in the transfer flow.
#
# 1. A partially received transfer had no terminal state: cancel is only reachable
#    from `requested`, so 18-of-24 with nobody intending to send the rest sat in the
#    Open queue forever. Closing short accepts the shortfall and finishes the
#    transfer, recording who accepted it and why.
#
#    Reuses the `completed` status rather than adding a seventh one, so the Open
#    queue clears and the completed-today panel picks it up; closed_short_at is what
#    distinguishes "everything arrived" from "we gave up on the rest".
#
# 2. A short receipt left no record of itself — the shortfall silently returned to
#    the sender's outstanding amount with no note of what happened.
class AddCloseShortAndReceiptNotesToTransfers < ActiveRecord::Migration[7.1]
  def change
    add_column :stock_transfers, :closed_short_at, :datetime
    add_column :stock_transfers, :closed_short_reason, :text
    add_reference :stock_transfers, :closed_short_by, type: :uuid, null: true,
      foreign_key: { to_table: :users, on_delete: :restrict }

    add_column :stock_transfer_shipments, :receipt_notes, :text
  end
end
