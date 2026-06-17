import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { id: String }

  connect() {
    if (this.hasIdValue && this.idValue === "print-agent" && this.isPageReload()) {
      this.clearDismissal()
    }

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
    this.notifyOffsetChange()
    return true
  }

  hide() {
    this.element.classList.add("hidden")
    this.notifyOffsetChange()
  }

  notifyOffsetChange() {
    requestAnimationFrame(() => {
      document.dispatchEvent(new CustomEvent("pos-banners:changed"))
    })
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

  isPageReload() {
    const [nav] = performance.getEntriesByType("navigation")
    if (nav?.type) return nav.type === "reload"

    return performance.navigation?.type === 1
  }
}
