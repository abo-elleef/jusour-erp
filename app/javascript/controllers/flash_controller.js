import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { dismissAfter: { type: Number, default: 3000 } }

  connect() {
    if (this.element.children.length === 0) return

    this.dismissTimeout = window.setTimeout(() => this.dismiss(), this.dismissAfterValue)
  }

  disconnect() {
    window.clearTimeout(this.dismissTimeout)
    window.clearTimeout(this.removeTimeout)
  }

  dismiss() {
    this.element.style.transition = "opacity 0.4s ease"
    this.element.style.opacity = "0"

    this.removeTimeout = window.setTimeout(() => {
      this.element.replaceChildren()
      this.element.style.opacity = ""
      this.element.style.transition = ""
      document.documentElement.style.setProperty("--flash-offset", "0px")
    }, 400)
  }
}
