# frozen_string_literal: true

# Per-branch switches for customer self-ordering from the public menu. Hours are
# wall-clock times in the company timezone; both blank means "whenever the menu
# is public". An unanswered request auto-rejects after the accept timeout.
class AddOnlineOrderingToLocations < ActiveRecord::Migration[7.1]
  def change
    add_column :locations, :online_ordering_enabled, :boolean, null: false, default: false
    add_column :locations, :online_open_time, :time
    add_column :locations, :online_close_time, :time
    add_column :locations, :online_accept_timeout_minutes, :integer, null: false, default: 10
    add_column :locations, :online_max_order_cents, :integer
  end
end
