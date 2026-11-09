import { Controller } from "@hotwired/stimulus"

// Every cart change replaces the whole cart, which would throw the basket back to
// the top. State lives at module level because each replacement builds a brand new
// controller instance: remember where the cashier had scrolled and how many lines
// there were, then on reconnect either stay put (count change, remove) or, when a
// new line was added, jump to the bottom so it is visible.
let savedScrollTop = null
let savedLines = null

export default class extends Controller {
  static values = { lines: Number }

  connect() {
    const grew = savedLines !== null && this.linesValue > savedLines
    const target = grew ? () => this.element.scrollHeight : () => savedScrollTop

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

  disconnect() {
    this.element.removeEventListener("scroll", this.onScroll)
  }
}
