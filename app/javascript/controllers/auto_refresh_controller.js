import { Controller } from "@hotwired/stimulus"

// Reloads the current page in place every few seconds, so a screen shared by several
// registers (the Tables board) stays current. Paused while the tab is hidden.
export default class extends Controller {
  static values = { interval: { type: Number, default: 15000 } }

  connect() {
    this.timer = setInterval(() => {
      if (document.hidden) return
      window.Turbo.visit(window.location.href, { action: "replace" })
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}
