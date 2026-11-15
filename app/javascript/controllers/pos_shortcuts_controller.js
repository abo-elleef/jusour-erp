import { Controller } from "@hotwired/stimulus"

// POS register keyboard shortcuts. F-keys and key *codes* (not characters), so
// they work the same with the keyboard on Arabic or English.
//   F1 or ? / ؟   help sheet          F2 or /   menu search
//   F4            new order           F8        place order (or place again)
//   F9            charge              1–9 / 0   Nth category / All
//   Esc           closes the payment popup
// The order buttons are looked up when the key is pressed (the cart is
// re-rendered by Turbo streams) through data-pos-shortcut="…" and clicked like a
// tap, so a disabled one (empty basket) simply does nothing.
// Nothing fires while another popup owns the keyboard (add item, payment, PIN,
// any open <dialog>) — those handle their own Enter / Esc.
const F_KEYS = { F1: "help", F2: "search", F4: "new-order", F8: "place-order", F9: "charge" }

export default class extends Controller {
  connect() {
    this.keydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.keydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.keydown)
  }

  keydown(event) {
    if (event.isComposing || event.defaultPrevented) return
    if (event.ctrlKey || event.metaKey || event.altKey) return

    if (event.key === "Escape" && this.paymentOpen()) {
      event.preventDefault()
      return this.closePayment()
    }

    const fAction = F_KEYS[event.key]
    if (fAction) {
      event.preventDefault() // F1 would open the browser's help page
      if (this.popupOpen() || event.repeat) return
      return this.run(fAction)
    }

    if (this.typing(event.target) || this.popupOpen()) return

    if (event.key === "?" || event.key === "؟") {
      event.preventDefault()
      return this.run("help")
    }
    // The key's position (code) for the Arabic layout, where that key types ظ;
    // the character itself as a fallback for keyboards that send no code.
    if ((event.code === "Slash" && !event.shiftKey) || event.key === "/") {
      event.preventDefault()
      return this.run("search")
    }
    const digit = event.shiftKey ? null : this.digit(event)
    if (digit !== null) {
      event.preventDefault()
      this.pickCategory(digit)
    }
  }

  digit(event) {
    const byCode = event.code?.match(/^(?:Digit|Numpad)(\d)$/)
    if (byCode) return Number(byCode[1])
    const index = "0123456789".indexOf(event.key)
    if (index >= 0 && event.key.length === 1) return index
    const arabic = "٠١٢٣٤٥٦٧٨٩".indexOf(event.key)
    return arabic >= 0 && event.key.length === 1 ? arabic : null
  }

  run(action) {
    if (action === "search") return this.searchController()?.focus()
    if (action === "help") return document.getElementById("pos-shortcuts-help")?.showModal()

    const button = document.querySelector(`[data-pos-shortcut="${action}"]`)
    if (!button || button.disabled) return
    button.click()
  }

  // 0 = All; 1–9 = the categories after it, in the order the rail shows them.
  pickCategory(n) {
    const buttons = [...document.querySelectorAll(".pos-category-btn")].filter((b) => b.getClientRects().length > 0)
    buttons[n]?.click()
  }

  searchController() {
    const el = document.querySelector('[data-controller~="pos-menu-search"]')
    return el && this.application.getControllerForElementAndIdentifier(el, "pos-menu-search")
  }

  typing(target) {
    return target instanceof Element && target.matches("input, textarea, select, [contenteditable]")
  }

  paymentOpen() {
    const modal = document.getElementById("payment-modal")
    return modal && !modal.classList.contains("hidden")
  }

  closePayment() {
    const pos = this.application.getControllerForElementAndIdentifier(this.element, "pos")
    pos?.closePayment()
  }

  popupOpen() {
    return Boolean(
      document.querySelector("#modifier_modal form") ||
      this.paymentOpen() ||
      document.querySelector("dialog[open]") ||
      document.querySelector('[data-manager-pin-modal-target="modal"]:not(.hidden)')
    )
  }
}
