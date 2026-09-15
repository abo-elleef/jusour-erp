import { Controller } from "@hotwired/stimulus"

// Toggles a password field between hidden and plain text. Swaps the eye icons
// and keeps the button's accessible label in sync with the current state.
export default class extends Controller {
  static targets = ["field", "showIcon", "hideIcon", "button"]
  static values = {
    showLabel: String,
    hideLabel: String
  }

  toggle(event) {
    event?.preventDefault()

    const revealed = this.fieldTarget.type === "password"
    this.fieldTarget.type = revealed ? "text" : "password"

    this.showIconTarget.classList.toggle("hidden", revealed)
    this.hideIconTarget.classList.toggle("hidden", !revealed)

    if (this.hasButtonTarget) {
      const label = revealed ? this.hideLabelValue : this.showLabelValue
      this.buttonTarget.setAttribute("aria-label", label)
      this.buttonTarget.setAttribute("title", label)
      this.buttonTarget.setAttribute("aria-pressed", revealed ? "true" : "false")
    }

    this.fieldTarget.focus()
  }
}
