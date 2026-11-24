# frozen_string_literal: true

# Branches that want every delivery order tied to a delivery area (SAQR's branch
# managers asked for it). Off by default, so other companies keep the area as an
# optional pick. Checked when an order is placed and when money is taken
# (Order#needs_delivery_area?); offline orders are never held up by it.
class AddRequireDeliveryAreaToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :require_delivery_area, :boolean, default: false, null: false
  end
end
