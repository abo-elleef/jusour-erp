# frozen_string_literal: true

# What a voucher is for, when that changes where its far side lands.
#
# A settlement voucher clears what it settles, and anything unallocated falls to
# the accrual account for its direction. A treasury adjustment has nothing to
# settle by definition — it is cash appearing in or leaving a treasury with no
# counterparty document — so its far side is equity, the way the old
# "adjust balance" action already posted it.
class AddPurposeToVouchers < ActiveRecord::Migration[7.1]
  def change
    add_column :vouchers, :purpose, :string, null: false, default: "settlement"
    add_index :vouchers, :purpose
  end
end
