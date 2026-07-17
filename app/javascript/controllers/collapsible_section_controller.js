import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "chevron"]
  static values  = { open: { type: Boolean, default: true } }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.contentTargets.forEach(row => row.classList.toggle("hidden", !this.openValue))
    this.chevronTargets.forEach(icon => icon.classList.toggle("-rotate-90", !this.openValue))
  }
}
