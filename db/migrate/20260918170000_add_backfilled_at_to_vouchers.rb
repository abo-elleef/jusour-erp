# frozen_string_literal: true

# Marks a voucher that documents cash which had already moved before vouchers
# existed, rather than moving it.
#
# Every expense and income taken before the switch posted its own treasury
# transaction and its own journal entry, and those are correct and internally
# consistent. Re-posting them through a voucher would either double the cash or
# force us to delete and rewrite historical treasury rows — and balance_after_cents
# is a stored running balance shown as a column on the treasury and supplier
# pages, so rewriting those rows would stamp today's balance onto years of
# history for no gain.
#
# So a backfilled voucher carries the number, the date and the allocation, and
# deliberately posts nothing. Anything summing voucher cash must exclude these
# or it will count the same money twice.
class AddBackfilledAtToVouchers < ActiveRecord::Migration[7.1]
  def change
    add_column :vouchers, :backfilled_at, :datetime
    add_index :vouchers, :backfilled_at
  end
end
