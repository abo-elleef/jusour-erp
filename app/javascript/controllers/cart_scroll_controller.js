import { Controller } from "@hotwired/stimulus"

// Every cart change replaces the whole cart, which would throw the basket back to
// the top. State lives at module level because each replacement builds a brand new
// controller instance: remember where the cashier had scrolled, and on reconnect
// either stay put (quantity +/−, remove, notes) or, right after an add, bring the
// line the add landed on into view.
//
// Lines are sorted by category and name (OrderItem.in_menu_order), so the added
// line can be anywhere in the list. The cart marks it with data-cart-added (the
// add action is the only one that does) and draws it highlighted; here it is
// scrolled to the middle of the basket and given a short pulse so the eye finds it.
let savedScrollTop = null

export default class extends Controller {
  static values = { lines: Number }

  connect() {
    const added = this.element.querySelector("[data-cart-added]")
    const target = added ? () => this.centredTop(added) : () => savedScrollTop

    // Only user scrolling updates the saved position, never our own restore.
    this.onScroll = () => { if (!this.restoring) savedScrollTop = this.element.scrollTop }

    if (this.linesValue > 0 && (added || savedScrollTop !== null)) {
      this.restoring = true
      const apply = () => { this.element.scrollTop = target() }
      apply()
      // The browser may still be settling layout (focus, fonts) right after a
      // replace; apply again once it has painted.
      requestAnimationFrame(() => {
        apply()
        savedScrollTop = this.element.scrollTop
        this.restoring = false
      })
    }
    if (added) this.pulse(added)

    this.element.addEventListener("scroll", this.onScroll, { passive: true })
  }

  // Scroll position that puts the line in the middle of the basket (or as near as
  // the list allows).
  centredTop(line) {
    const box = this.element.getBoundingClientRect()
    const lineBox = line.getBoundingClientRect()
    const offset = lineBox.top - box.top + this.element.scrollTop
    return Math.max(0, offset - (this.element.clientHeight - lineBox.height) / 2)
  }

  // A brief grow-and-settle so the eye catches the line; the amber highlight itself
  // stays until the next basket change.
  pulse(line) {
    if (typeof line.animate !== "function") return
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return
    line.animate(
      [
        { transform: "scale(1)", boxShadow: "0 0 0 0 rgba(251, 191, 36, 0.7)" },
        { transform: "scale(1.02)", boxShadow: "0 0 0 8px rgba(251, 191, 36, 0.35)" },
        { transform: "scale(1)", boxShadow: "0 0 0 0 rgba(251, 191, 36, 0)" }
      ],
      { duration: 700, easing: "ease-out" }
    )
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
  }
}
