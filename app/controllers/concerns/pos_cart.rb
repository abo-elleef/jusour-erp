# frozen_string_literal: true

# Which cart the register is on.
#
# It used to live only in session[:current_order_id], and the session is a cookie
# that the last response to arrive writes back whole. The register page keeps
# requests going in the background (print polling, print pickups, notifications,
# Turbo hover prefetch). One that left before an add-item response came back
# returned the older cookie, without the cart, and the register forgot it: the
# next item went into a new order, or picking the order type or customer started
# an empty one and left the basket behind as a draft (SAQR, 2026-11-21).
#
# So the register page sends the cart it shows in the X-Pos-Cart header with
# every cart action (blank while the cart is still unsaved), and that wins over
# the session. Responses send the cart back in the same header so the page always
# knows it. Rendering the register itself (GET /pos) still follows the session:
# New order, resume, table open and unlock point it there and then redirect.
module PosCart
  extend ActiveSupport::Concern

  HEADER = "X-Pos-Cart"

  included do
    after_action :expose_pos_cart
  end

  private

  # The cart's id: the page's when it said, else the session's.
  def pos_cart_id
    pos_cart_from_page? ? request.headers[HEADER].presence : session[:current_order_id]
  end

  # The cart, if it can still take changes. When the page named it, the session is
  # put back in step, so a redirect back to the register shows the same cart.
  def pos_cart_order
    id = pos_cart_id
    return if id.blank?

    order = Order.cart_editable.find_by(id: id)
    session[:current_order_id] = order.id if order && pos_cart_from_page? && session[:current_order_id] != order.id
    order
  end

  def pos_cart_from_page?
    request.headers.key?(HEADER) && !pos_register_render?
  end

  def pos_register_render?
    false
  end

  def expose_pos_cart
    return if pos_register_render?
    return unless @order.is_a?(Order)

    editable = @order.persisted? && (@order.draft? || @order.editing_placed?)
    response.set_header(HEADER, editable ? @order.id.to_s : "")
  end
end
