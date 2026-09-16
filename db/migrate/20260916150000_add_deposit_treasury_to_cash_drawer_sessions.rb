# frozen_string_literal: true

# Where the drawer's cash goes when the shift ends.
#
# Opening a drawer already carries a float in from another treasury, every time.
# Nothing ever carried it back out, so drawers only ever grew — one in this data
# is sitting on 2,910.00 it was never emptied of. Naming a destination at close
# lets the counted cash leave the drawer for the safe it physically goes into,
# and returns the drawer to zero where it belongs.
class AddDepositTreasuryToCashDrawerSessions < ActiveRecord::Migration[7.1]
  def change
    add_reference :cash_drawer_sessions, :deposit_treasury, type: :uuid, null: true,
                  foreign_key: { to_table: :treasuries }
  end
end
