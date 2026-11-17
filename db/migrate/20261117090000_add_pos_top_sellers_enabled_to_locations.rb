# frozen_string_literal: true

# Per-branch switch for the "Most sold" row on the register. Off by default, so
# no cashier's screen changes until an admin turns it on for that branch.
class AddPosTopSellersEnabledToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :pos_top_sellers_enabled, :boolean, default: false, null: false
  end
end
