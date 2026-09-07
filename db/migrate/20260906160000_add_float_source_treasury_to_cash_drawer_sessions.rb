# frozen_string_literal: true

# The opening float is carried into the drawer from a safe, so the session has to
# record which treasury it came out of. Without it the float had nowhere to be
# credited and the ledger charged it to equity instead.
class AddFloatSourceTreasuryToCashDrawerSessions < ActiveRecord::Migration[7.1]
  def change
    add_reference :cash_drawer_sessions, :float_source_treasury,
      type: :uuid, null: true, foreign_key: { to_table: :treasuries }
  end
end
