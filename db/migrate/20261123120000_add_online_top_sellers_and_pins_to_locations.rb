# frozen_string_literal: true

# The "Most sold" row can now show on the register, the online menu (which the
# call center also orders from), both or neither, and a manager can pin items
# that come first, ahead of the ones filled in from the last 14 days of sales.
class AddOnlineTopSellersAndPinsToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :online_top_sellers_enabled, :boolean, default: false, null: false
    add_column :locations, :top_seller_pinned_item_ids, :uuid, array: true, default: [], null: false
  end
end
