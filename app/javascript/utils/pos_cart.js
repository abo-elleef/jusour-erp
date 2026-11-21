// The cart the register shows, sent with every request the register makes so the
// server acts on that cart and not on whatever the session cookie last said (see
// app/controllers/concerns/pos_cart.rb for why the cookie can't be trusted).
// It lives on #pos-cart-ref, rendered by the register page, and follows the
// X-Pos-Cart header on responses. Off the register there is no ref and no header.
export const POS_CART_HEADER = "X-Pos-Cart"

function ref() {
  return document.getElementById("pos-cart-ref")
}

export function posCartHeaders() {
  const el = ref()
  return el ? { [POS_CART_HEADER]: el.dataset.orderId || "" } : {}
}

export function rememberPosCart(response) {
  const el = ref()
  const headers = response?.headers
  if (!el || !headers?.has(POS_CART_HEADER)) return
  el.dataset.orderId = headers.get(POS_CART_HEADER) || ""
}
