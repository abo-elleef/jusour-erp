# frozen_string_literal: true

# Where a branch's drawers are banked at close.
#
# The destination used to be picked by the cashier at count-down, which made the
# same branch's takings land wherever whoever happened to be closing chose. It
# belongs to the branch and is set once by an admin; the cashier only counts.
class AddDepositTreasuryToLocations < ActiveRecord::Migration[7.1]
  def change
    add_reference :locations, :deposit_treasury, type: :uuid, null: true,
                  foreign_key: { to_table: :treasuries }
  end
end
