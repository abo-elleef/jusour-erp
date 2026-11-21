# frozen_string_literal: true

# The register keeps one cart in the session. When the cashier moves to another
# one (New order, resuming an order, opening a table, unlocking a placed order),
# the cart being left is deleted if nothing was ever put in it. A cart with items
# is kept: the cashier may come back to it.
module AbandonedCartCleanup
  extend ActiveSupport::Concern

  private

  def discard_abandoned_cart!(keep_id: nil)
    # On the register the page names its own cart (PosCart); elsewhere it is the session's.
    id = respond_to?(:pos_cart_id, true) ? pos_cart_id : session[:current_order_id]
    return if id.blank? || id.to_s == keep_id.to_s

    order = Order.find_by(id: id, user_id: current_user.id)
    Orders::DiscardEmptyDraftService.call(order, user: current_user) if order
  end
end
