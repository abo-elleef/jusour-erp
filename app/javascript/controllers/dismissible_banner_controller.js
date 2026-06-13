import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { id: String }

  connect() {
    if (this.isDismissed()) this.hide()
  }

  dismiss(event) {
    event?.preventDefault()
    if (this.hasIdValue) sessionStorage.setItem(this.storageKey(), "1")
    this.hide()
    this.element.dispatchEvent(new CustomEvent("banner:dismissed", { bubbles: true, detail: { id: this.idValue } }))
  }

  show() {
    if (this.isDismissed()) return false

    this.element.classList.remove("hidden")
    return true
  }

  hide() {
    this.element.classList.add("hidden")
  }

  isDismissed() {
    if (!this.hasIdValue) return false
    return sessionStorage.getItem(this.storageKey()) === "1"
  }

  clearDismissal() {
    if (!this.hasIdValue) return
    sessionStorage.removeItem(this.storageKey())
  }

  storageKey() {
    return `saqr_banner_dismissed_${this.idValue}`
  }
}
