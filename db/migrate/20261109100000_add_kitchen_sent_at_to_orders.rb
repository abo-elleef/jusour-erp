# frozen_string_literal: true

# When the kitchen / bar tickets were last printed for an order, so paying after an
# early "send to kitchen" does not print them a second time by default.
class AddKitchenSentAtToOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :kitchen_sent_at, :datetime
  end
end
