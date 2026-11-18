# frozen_string_literal: true

# The story of a self-order for later review: the "Who is this?" check as it
# stood when the request came in and when it was decided, the cashier's own words
# on a rejection, and whether they blocked the phone.
class AddReviewDetailsToOnlineOrderRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :online_order_requests, :checks, :jsonb, null: false, default: {}
    add_column :online_order_requests, :reject_note, :text
    add_column :online_order_requests, :blocked_phone, :boolean, null: false, default: false
  end
end
