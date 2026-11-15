import { Controller } from "@hotwired/stimulus"

// Every cart change replaces the whole cart, which would throw the basket back to
// the top. State lives at module level because each replacement builds a brand new
// controller instance: remember where the cashier had scrolled and how many lines
// there were, then on reconnect either stay put (count change, remove) or, when a
// new line was added, bring that line into view. Lines are sorted by category and
// name (OrderItem.in_menu_order), so the new line is not always the last one: the
// cart marks it with data-cart-newest.
let savedScrollTop = null
let savedLines = null

export default class extends Controller {
  static values = { lines: Number }

  connect() {
    const grew = savedLines !== null && this.linesValue > savedLines
    const target = grew ? () => this.newestLineTop() : () => savedScrollTop

    // Only user scrolling updates the saved position, never our own restore.
    this.onScroll = () => { if (!this.restoring) savedScrollTop = this.element.scrollTop }

    if (this.linesValue > 0 && (grew || savedScrollTop !== null)) {
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

    savedLines = this.linesValue
    this.element.addEventListener("scroll", this.onScroll, { passive: true })
  }

  // Scroll position that shows the newest line, centred when the list is long
  // enough; the bottom when no line is marked.
  newestLineTop() {
    const line = this.element.querySelector("[data-cart-newest]")
    if (!line) return this.element.scrollHeight
    const box = this.element.getBoundingClientRect()
    const lineBox = line.getBoundingClientRect()
    const offset = lineBox.top - box.top + this.element.scrollTop
    return Math.max(0, offset - (this.element.clientHeight - lineBox.height) / 2)
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
  }
}
